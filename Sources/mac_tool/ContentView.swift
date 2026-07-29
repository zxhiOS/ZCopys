import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("搜索剪贴板", text: $appState.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .medium))
                        .focused($isSearchFocused)

                    Button {
                        appState.clearHistory()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help("清空记录")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "暂无剪贴板历史",
                        systemImage: "doc.on.clipboard",
                        description: Text("复制文本、文件或图片后会显示在这里")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredItems) { item in
                            Button {
                                appState.copyItemAndClose(item)
                            } label: {
                                ClipboardRow(item: item)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(item.id == appState.selectedItemID ? Color.blue.opacity(0.14) : Color.white.opacity(0.55))
                                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                            )
                            .contextMenu {
                                Button("复制") {
                                    appState.copyItemAndClose(item)
                                }
                                Button(item.isPinned ? "取消置顶" : "置顶") {
                                    appState.clipboardStore.togglePin(item)
                                }
                                Button("删除") {
                                    appState.delete(item)
                                }
                            }
                        }
                        }
                        .padding(.vertical, 12)
                    }
                }
            }

            if let feedbackMessage = appState.feedbackMessage {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(feedbackMessage)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.78))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        Spacer()
                    }
                    .padding(.bottom, 18)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(width: 720, height: 520)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
        .onAppear {
            isSearchFocused = true
            appState.syncSelection()
        }
        .onChange(of: appState.searchText) { _, _ in
            appState.syncSelection()
        }
        .onChange(of: appState.shouldFocusSearch) { _, newValue in
            guard newValue else { return }
            isSearchFocused = true
            appState.shouldFocusSearch = false
        }
        .animation(.snappy, value: appState.feedbackMessage != nil)
    }

    private var filteredItems: [ClipboardItem] {
        appState.clipboardStore.filteredItems(matching: appState.searchText)
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.kind.rawValue.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if item.isPinned {
                        Text("PIN")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.yellow.opacity(0.25))
                            .clipShape(Capsule())
                    }
                }

                Text(item.value)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if item.kind == .file || item.kind == .image {
                    Text(item.kind == .file ? "可回填文件路径" : "可回填图片")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(item.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
