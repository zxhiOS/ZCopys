import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: 22,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 22,
                style: .continuous
            )
            .fill(.ultraThinMaterial)

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                ZStack {
                    if appState.isLinkEditorPresented {
                        linkEditorOverlay
                    } else {
                        cardGallery
                    }

                    if let feedbackMessage = appState.feedbackMessage {
                        VStack {
                            Spacer()
                            Text(feedbackMessage)
                                .font(.callout.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.black.opacity(0.78))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                                .padding(.bottom, 18)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 22,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 22,
                style: .continuous
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 22,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 22,
                style: .continuous
            )
            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear {
            appState.syncSelection()
        }
        .onChange(of: appState.selectedTab) { _, _ in
            appState.syncSelection()
        }
        .onChange(of: appState.searchText) { _, _ in
            appState.syncSelection()
        }
        .onChange(of: appState.shouldFocusSearch) { _, newValue in
            guard newValue else { return }
            appState.requestTypingFocus()
            appState.isSearchExpanded = true
            isSearchFocused = true
            appState.shouldFocusSearch = false
        }
        .onChange(of: appState.isSearchExpanded) { _, expanded in
            if expanded {
                appState.requestTypingFocus()
                isSearchFocused = true
            }
        }
        .onChange(of: appState.isLinkEditorPresented) { _, presented in
            if presented {
                appState.requestTypingFocus()
            }
        }
        .animation(.snappy, value: appState.feedbackMessage != nil)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            searchControl

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                tabButton(
                    title: "Clipboard",
                    icon: "clock",
                    isSelected: appState.selectedTab == .clipboard
                ) {
                    appState.selectedTab = .clipboard
                    appState.syncSelection()
                }

                usefulLinksTabButton

                if appState.selectedTab == .usefulLinks {
                    Button {
                        appState.beginAddUsefulLink()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Add Useful Link")
                }
            }

            Spacer(minLength: 0)

            Menu {
                Button("Clear Current Tab", role: .destructive) {
                    appState.clearCurrentTab()
                }
                if !appState.isAccessibilityTrusted {
                    Button("Request Accessibility Permission") {
                        appState.requestAccessibilityPermission()
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28, height: 28)
            .help("More")
        }
    }

    private var searchControl: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy) {
                    appState.isSearchExpanded.toggle()
                    if appState.isSearchExpanded {
                        appState.requestTypingFocus()
                        isSearchFocused = true
                    } else {
                        appState.collapseSearchIfNeeded()
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Search")

            if appState.isSearchExpanded {
                TextField("Search", text: $appState.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .focused($isSearchFocused)
                    .frame(minWidth: 160, idealWidth: 220, maxWidth: 320)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                    )
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                    .onAppear {
                        DispatchQueue.main.async {
                            isSearchFocused = true
                        }
                    }
            }
        }
        .frame(minWidth: 28, alignment: .leading)
        .animation(.snappy, value: appState.isSearchExpanded)
    }

    private var usefulLinksTabButton: some View {
        Button {
            appState.selectedTab = .usefulLinks
            appState.syncSelection()
        } label: {
            HStack(spacing: 6) {
                if !appState.usefulLinksStore.items.isEmpty {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                }
                Text("Useful Links")
                    .font(.system(size: 13, weight: appState.selectedTab == .usefulLinks ? .semibold : .medium))
            }
            .foregroundStyle(appState.selectedTab == .usefulLinks ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(appState.selectedTab == .usefulLinks ? Color.black.opacity(0.85) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func tabButton(
        title: String,
        icon: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? Color.black.opacity(0.85) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Gallery

    @ViewBuilder
    private var cardGallery: some View {
        switch appState.selectedTab {
        case .clipboard:
            if filteredClipboard.isEmpty {
                emptyState(
                    title: "No Clipboard History",
                    systemImage: "doc.on.clipboard",
                    description: "Copied text, files, or images will appear here"
                )
            } else {
                horizontalCards {
                    ForEach(Array(filteredClipboard.enumerated()), id: \.element.id) { index, item in
                        Button {
                            appState.activateClipboardItem(item)
                        } label: {
                            HistoryCard(
                                item: item,
                                index: index + 1,
                                isSelected: item.id == appState.selectedItemID
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Copy") {
                                appState.activateClipboardItem(item)
                            }
                            Button(item.isPinned ? "Unpin" : "Pin") {
                                appState.clipboardStore.togglePin(item)
                            }
                            Button("Add to Useful Links") {
                                appState.addClipboardItemToUsefulLinks(item)
                            }
                            Button("Delete", role: .destructive) {
                                appState.delete(item)
                            }
                        }
                    }
                }
            }
        case .usefulLinks:
            if filteredLinks.isEmpty {
                emptyState(
                    title: "No Useful Links",
                    systemImage: "link",
                    description: "Tap + to add a link, or favorite items from Clipboard"
                )
            } else {
                horizontalCards {
                    ForEach(Array(filteredLinks.enumerated()), id: \.element.id) { index, link in
                        Button {
                            appState.activateUsefulLink(link)
                        } label: {
                            LinkCard(
                                link: link,
                                index: index + 1,
                                isSelected: link.id == appState.selectedItemID
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Open / Copy") {
                                appState.activateUsefulLink(link)
                            }
                            Button("Edit") {
                                appState.beginEditUsefulLink(link)
                            }
                            Button(link.isPinned ? "Unpin" : "Pin") {
                                appState.usefulLinksStore.togglePin(link)
                            }
                            Button("Delete", role: .destructive) {
                                appState.usefulLinksStore.delete(link)
                                appState.syncSelection()
                            }
                        }
                    }
                }
            }
        }
    }

    private func horizontalCards<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                content()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private func emptyState(title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Link editor

    private var linkEditorOverlay: some View {
        VStack(spacing: 16) {
            Text(appState.editingLinkID == nil ? "Add Useful Link" : "Edit Useful Link")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Optional title", text: $appState.linkEditorTitle)
                    .textFieldStyle(.roundedBorder)

                Text("URL / Text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("https://… or any text", text: $appState.linkEditorBody)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    appState.cancelLinkEditor()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    appState.saveLinkEditor()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(appState.linkEditorBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        )
        .padding(24)
    }

    // MARK: - Data

    private var filteredClipboard: [ClipboardItem] {
        appState.clipboardStore.filteredItems(matching: appState.searchText)
    }

    private var filteredLinks: [UsefulLink] {
        appState.usefulLinksStore.filteredItems(matching: appState.searchText)
    }
}

// MARK: - Cards

struct HistoryCard: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool

    var body: some View {
        let tone = CardPresentation.tone(forClipboardKind: item.kind, value: item.value)
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(CardPresentation.displayKindLabel(for: item.kind))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(CardPresentation.relativeTime(from: item.lastUsedAt))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: headerIcon)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.color)

            Text(item.value)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(8)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
                .background(Color.white)

            HStack {
                Text(CardPresentation.characterCountLabel(for: characterCountSource))
                Spacer()
                Label("\(index)", systemImage: "list.bullet.rectangle")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white)
        }
        .frame(width: 200, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private var characterCountSource: String {
        switch item.kind {
        case .image:
            return item.value
        default:
            return item.payload
        }
    }

    private var headerIcon: String {
        switch item.kind {
        case .file:
            return "doc.on.doc"
        case .url:
            return "link"
        case .image:
            return "photo"
        default:
            return "bolt.fill"
        }
    }
}

struct LinkCard: View {
    let link: UsefulLink
    let index: Int
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Link")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(CardPresentation.relativeTime(from: link.lastUsedAt))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "link")
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardHeaderTone.link.color)

            VStack(alignment: .leading, spacing: 6) {
                Text(link.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(link.urlOrText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(Color.white)

            HStack {
                Text(CardPresentation.characterCountLabel(for: link.urlOrText))
                Spacer()
                Label("\(index)", systemImage: "list.bullet.rectangle")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white)
        }
        .frame(width: 200, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}
