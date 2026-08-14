import Foundation
import CloudKit
import Security

enum SyncMerge {
    static func categories(local: [PanelCategory], remote: [PanelCategory]) -> [PanelCategory] {
        var map: [UUID: PanelCategory] = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for item in remote {
            if let existing = map[item.id] {
                if item.updatedAt > existing.updatedAt {
                    map[item.id] = item
                }
            } else {
                map[item.id] = item
            }
        }
        return map.values.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.createdAt < $1.createdAt
        }
    }

    static func links(local: [UsefulLink], remote: [UsefulLink]) -> [UsefulLink] {
        var map: [UUID: UsefulLink] = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for item in remote {
            if let existing = map[item.id] {
                if item.updatedAt > existing.updatedAt {
                    map[item.id] = item
                }
            } else {
                map[item.id] = item
            }
        }
        return Array(map.values)
    }
}

@MainActor
final class CloudKitSyncEngine: ObservableObject {
    enum AccountState: Equatable {
        case unknown
        case available
        case noAccount
        case restricted
        case temporarilyUnavailable
        case couldNotDetermine
    }

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var accountState: AccountState = .unknown
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isStarted, isEnabled {
                Task { await syncNow(reason: "enabled") }
            }
        }
    }

    private let categoryStore: CategoryStore
    private let usefulLinksStore: UsefulLinksStore
    /// When false (unit tests), never touch CloudKit — constructing `CKContainer` crashes XCTest.
    private let usesCloudKit: Bool
    private let containerIdentifier: String
    private var container: CKContainer?
    private var database: CKDatabase?
    private var pushTask: Task<Void, Never>?
    private var isApplyingRemote = false
    private var isStarted = false

    private static let enabledKey = "zcopys.icloudSyncEnabled"
    private static let categoryRecordType = "ZCategory"
    private static let linkRecordType = "ZLinkItem"

    init(
        categoryStore: CategoryStore,
        usefulLinksStore: UsefulLinksStore,
        containerIdentifier: String = "iCloud.com.local.zcopys",
        usesCloudKit: Bool = true
    ) {
        self.categoryStore = categoryStore
        self.usefulLinksStore = usefulLinksStore
        self.usesCloudKit = usesCloudKit
        self.containerIdentifier = containerIdentifier
        // Default off in tests so toggling sync in AppStateTests cannot hit CloudKit.
        if usesCloudKit {
            self.isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        } else {
            self.isEnabled = false
        }

        categoryStore.onChange = { [weak self] in
            self?.schedulePush()
        }
        usefulLinksStore.onChange = { [weak self] in
            self?.schedulePush()
        }
    }

    func start() {
        guard usesCloudKit else { return }
        isStarted = true
        guard Self.hasICloudEntitlement(for: containerIdentifier) else {
            accountState = .couldNotDetermine
            lastError = "CloudKit 未启用签名权限：请在 Apple Developer 开启 CloudKit，并用 ENABLE_ICLOUD_ENTITLEMENTS=1 重新打包"
            return
        }
        ensureCloudKitReady()
        Task {
            await refreshAccountStatus()
            if isEnabled {
                await syncNow(reason: "launch")
            }
        }
    }

    /// `CKContainer` SIGTRAPs when the process lacks iCloud entitlements (XCTest / local signing).
    private static func hasICloudEntitlement(for containerIdentifier: String) -> Bool {
        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(
            URL(fileURLWithPath: Bundle.main.bundlePath) as CFURL,
            [],
            &staticCode
        )
        guard status == errSecSuccess, let staticCode else {
            // Non-bundled `swift run` / tests: refuse CloudKit to avoid crash.
            return false
        }
        var info: CFDictionary?
        let copyStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        )
        guard copyStatus == errSecSuccess,
              let info = info as? [String: Any],
              let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        else {
            return false
        }
        let services = entitlements["com.apple.developer.icloud-services"] as? [String] ?? []
        guard services.contains("CloudKit") else { return false }
        let containers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] ?? []
        return containers.contains(containerIdentifier)
    }

    private func ensureCloudKitReady() {
        guard usesCloudKit, container == nil else { return }
        guard Self.hasICloudEntitlement(for: containerIdentifier) else { return }
        let ck = CKContainer(identifier: containerIdentifier)
        container = ck
        database = ck.privateCloudDatabase
    }

    func refreshAccountStatus() async {
        guard usesCloudKit else {
            accountState = .couldNotDetermine
            return
        }
        guard Self.hasICloudEntitlement(for: containerIdentifier) else {
            accountState = .couldNotDetermine
            lastError = "CloudKit 未启用签名权限：请在 Apple Developer 开启 CloudKit，并用 ENABLE_ICLOUD_ENTITLEMENTS=1 重新打包"
            return
        }
        ensureCloudKitReady()
        guard let container else { return }
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                accountState = .available
            case .noAccount:
                accountState = .noAccount
            case .restricted:
                accountState = .restricted
            case .temporarilyUnavailable:
                accountState = .temporarilyUnavailable
            case .couldNotDetermine:
                accountState = .couldNotDetermine
            @unknown default:
                accountState = .couldNotDetermine
            }
        } catch {
            accountState = .couldNotDetermine
            lastError = error.localizedDescription
        }
    }

    func syncNow(reason: String) async {
        guard usesCloudKit else { return }
        guard isStarted else { return }
        guard isEnabled else { return }
        guard !isSyncing else { return }
        guard Self.hasICloudEntitlement(for: containerIdentifier) else {
            lastError = "CloudKit 未启用签名权限：请在 Apple Developer 开启 CloudKit，并用 ENABLE_ICLOUD_ENTITLEMENTS=1 重新打包"
            accountState = .couldNotDetermine
            return
        }
        ensureCloudKitReady()
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        await refreshAccountStatus()
        guard accountState == .available else {
            lastError = accountStatusMessage
            return
        }

        do {
            let remoteCategories = try await fetchAllCategories()
            let remoteLinks = try await fetchAllLinks()

            let mergedCategories = SyncMerge.categories(
                local: categoryStore.categories,
                remote: remoteCategories
            )
            let mergedLinks = SyncMerge.links(
                local: usefulLinksStore.items,
                remote: remoteLinks
            )

            isApplyingRemote = true
            categoryStore.replaceAll(mergedCategories)
            usefulLinksStore.replaceAll(mergedLinks)
            isApplyingRemote = false

            try await pushAll(categories: mergedCategories, links: mergedLinks)
            lastSyncAt = Date()
            lastError = nil
            print("CloudKit sync OK (\(reason))")
        } catch {
            lastError = friendlyError(error)
            print("CloudKit sync failed: \(error)")
        }
    }

    var accountStatusMessage: String {
        switch accountState {
        case .available:
            return "iCloud 已就绪"
        case .noAccount:
            return "未登录 Apple ID，请在系统设置中登录 iCloud"
        case .restricted:
            return "iCloud 受限，无法同步"
        case .temporarilyUnavailable:
            return "iCloud 暂时不可用，请稍后重试"
        case .couldNotDetermine, .unknown:
            return "无法确认 iCloud 状态（请检查 App 的 CloudKit 权限与容器配置）"
        }
    }

    private func schedulePush() {
        guard usesCloudKit, isStarted, isEnabled, !isApplyingRemote else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, !Task.isCancelled else { return }
            await self.syncNow(reason: "localChange")
        }
    }

    // MARK: - Fetch

    private func fetchAllCategories() async throws -> [PanelCategory] {
        try await fetchAll(recordType: Self.categoryRecordType).compactMap(Self.category(from:))
    }

    private func fetchAllLinks() async throws -> [UsefulLink] {
        try await fetchAll(recordType: Self.linkRecordType).compactMap(Self.link(from:))
    }

    private func fetchAll(recordType: String) async throws -> [CKRecord] {
        guard let database else { return [] }
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        var results: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                page = try await database.records(continuingMatchFrom: cursor)
            } else {
                page = try await database.records(matching: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 200)
            }
            for (_, result) in page.matchResults {
                if let record = try? result.get() {
                    results.append(record)
                }
            }
            cursor = page.queryCursor
        } while cursor != nil

        return results
    }

    // MARK: - Push

    private func pushAll(categories: [PanelCategory], links: [UsefulLink]) async throws {
        guard let database else { return }
        var records: [CKRecord] = []
        records.append(contentsOf: categories.map(Self.record(from:)))
        records.append(contentsOf: links.map(Self.record(from:)))
        guard !records.isEmpty else { return }

        // Chunk to stay under CloudKit op limits.
        let chunkSize = 100
        var index = 0
        while index < records.count {
            let end = min(index + chunkSize, records.count)
            let chunk = Array(records[index..<end])
            let result = try await database.modifyRecords(saving: chunk, deleting: [], savePolicy: .changedKeys)
            for (_, saveResult) in result.saveResults {
                if case .failure(let error) = saveResult {
                    throw error
                }
            }
            index = end
        }
    }

    // MARK: - Mapping

    private static func record(from category: PanelCategory) -> CKRecord {
        let recordID = CKRecord.ID(recordName: "category-\(category.id.uuidString)")
        let record = CKRecord(recordType: categoryRecordType, recordID: recordID)
        record["id"] = category.id.uuidString as CKRecordValue
        record["name"] = category.name as CKRecordValue
        record["sortOrder"] = category.sortOrder as CKRecordValue
        record["createdAt"] = category.createdAt as CKRecordValue
        record["updatedAt"] = category.updatedAt as CKRecordValue
        return record
    }

    private static func record(from link: UsefulLink) -> CKRecord {
        let recordID = CKRecord.ID(recordName: "link-\(link.id.uuidString)")
        let record = CKRecord(recordType: linkRecordType, recordID: recordID)
        record["id"] = link.id.uuidString as CKRecordValue
        record["title"] = link.title as CKRecordValue
        record["urlOrText"] = link.urlOrText as CKRecordValue
        record["createdAt"] = link.createdAt as CKRecordValue
        record["lastUsedAt"] = link.lastUsedAt as CKRecordValue
        record["updatedAt"] = link.updatedAt as CKRecordValue
        record["isPinned"] = (link.isPinned ? 1 : 0) as CKRecordValue
        if let categoryId = link.categoryId {
            record["categoryId"] = categoryId.uuidString as CKRecordValue
        } else {
            record["categoryId"] = "" as CKRecordValue
        }
        return record
    }

    private static func category(from record: CKRecord) -> PanelCategory? {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = record["name"] as? String else {
            return nil
        }
        let sortOrder = record["sortOrder"] as? Int ?? 0
        let createdAt = record["createdAt"] as? Date ?? Date()
        let updatedAt = record["updatedAt"] as? Date ?? createdAt
        return PanelCategory(
            id: id,
            name: name,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func link(from record: CKRecord) -> UsefulLink? {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let title = record["title"] as? String,
              let urlOrText = record["urlOrText"] as? String else {
            return nil
        }
        let createdAt = record["createdAt"] as? Date ?? Date()
        let lastUsedAt = record["lastUsedAt"] as? Date ?? createdAt
        let updatedAt = record["updatedAt"] as? Date ?? lastUsedAt
        let isPinned = ((record["isPinned"] as? Int) ?? 0) != 0
        let categoryRaw = record["categoryId"] as? String ?? ""
        let categoryId = categoryRaw.isEmpty ? nil : UUID(uuidString: categoryRaw)
        return UsefulLink(
            id: id,
            title: title,
            urlOrText: urlOrText,
            createdAt: createdAt,
            lastUsedAt: lastUsedAt,
            updatedAt: updatedAt,
            isPinned: isPinned,
            categoryId: categoryId
        )
    }

    private func friendlyError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == CKErrorDomain {
            switch CKError.Code(rawValue: ns.code) {
            case .notAuthenticated:
                return "未登录 iCloud"
            case .networkUnavailable, .networkFailure:
                return "网络不可用"
            case .quotaExceeded:
                return "iCloud 空间不足"
            case .serverRejectedRequest, .invalidArguments:
                return "CloudKit 容器未配置：请在 Apple Developer 为 Bundle ID 开启 CloudKit（iCloud.com.local.zcopys）"
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
