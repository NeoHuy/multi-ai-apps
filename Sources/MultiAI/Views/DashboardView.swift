import AppKit
import MultiAICore
import SwiftUI

enum SidebarSelection: Hashable {
    case all
    case running
    case appGroup(sourceAppPath: String)
}

struct DashboardView: View {
    @Bindable var store: InstanceStore
    @Bindable var uiState: AppUIState

    @State private var selection: SidebarSelection? = .all
    @State private var searchText: String = ""
    @State private var editingInstance: AppInstance?

    private struct AppGroupItem: Identifiable {
        let id: String
        let appName: String
        let count: Int
    }

    private var appGroups: [AppGroupItem] {
        let grouped = Dictionary(grouping: store.instances, by: \.sourceAppPath)
        return grouped.map { path, items in
            AppGroupItem(
                id: path,
                appName: items.first?.sourceAppName ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                count: items.count
            )
        }
        .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    private var filteredInstances: [AppInstance] {
        let base: [AppInstance]
        switch selection ?? .all {
        case .all:
            base = store.instances
        case .running:
            base = store.runningInstances
        case .appGroup(let path):
            base = store.instances.filter { $0.sourceAppPath == path }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.sourceAppName.localizedCaseInsensitiveContains(q)
                || ($0.targetURL?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private var navigationTitleText: String {
        switch selection ?? .all {
        case .all:
            return "All Accounts"
        case .running:
            return "Running Now"
        case .appGroup(let path):
            return appGroups.first(where: { $0.id == path })?.appName ?? "Accounts"
        }
    }

    private var quickStartApps: [InstalledApp] {
        let priority = store.installedApps.filter(\.isPriorityAIApp)
        return Array(priority.prefix(4))
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 280)
        } detail: {
            detailContent
        }
        .navigationTitle(navigationTitleText)
        .searchable(text: $searchText, prompt: "Tìm tài khoản hoặc ứng dụng...")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button {
                        store.tileRunning(for: filteredInstances, layout: .sideBySide)
                    } label: {
                        Label("Chia đều Side-by-Side (đang chạy)", systemImage: WindowTileLayout.sideBySide.systemImage)
                    }

                    Button {
                        store.tileRunning(for: filteredInstances, layout: .grid)
                    } label: {
                        Label("Chia lưới Grid (đang chạy)", systemImage: WindowTileLayout.grid.systemImage)
                    }

                    Button {
                        store.tileRunning(for: filteredInstances, layout: .stacked)
                    } label: {
                        Label("Chia dọc Stacked (đang chạy)", systemImage: WindowTileLayout.stacked.systemImage)
                    }

                    Divider()

                    Button {
                        store.launchAndTile(filteredInstances, layout: .sideBySide)
                    } label: {
                        Label("Mở tất cả & Chia Side-by-Side", systemImage: "rectangle.split.2x1.fill")
                    }
                    .disabled(filteredInstances.isEmpty)
                } label: {
                    Label("Chia cửa sổ", systemImage: "rectangle.split.2x1")
                }
                .help("Sắp xếp các cửa sổ tài khoản đang chạy")

                Button {
                    uiState.openAddAccount()
                } label: {
                    Label("Thêm Tài khoản", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $uiState.showingAddSheet) {
            AddEditInstanceSheet(
                store: store,
                editingInstance: nil,
                initialApp: uiState.preselectedApp,
                initialURL: uiState.preselectedURL
            )
        }
        .sheet(item: $editingInstance) { instance in
            AddEditInstanceSheet(store: store, editingInstance: instance)
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Tổng quan") {
                    Label {
                        HStack {
                            Text("Tất cả tài khoản")
                            Spacer()
                            countPill(store.instances.count, color: .secondary)
                        }
                    } icon: {
                        Image(systemName: "square.stack.3d.up")
                    }
                    .tag(SidebarSelection.all)

                    Label {
                        HStack {
                            Text("Đang chạy")
                            Spacer()
                            if !store.runningInstances.isEmpty {
                                countPill(store.runningInstances.count, color: .green)
                            }
                        }
                    } icon: {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .tag(SidebarSelection.running)
                }

                if !appGroups.isEmpty {
                    Section("Ứng dụng") {
                        ForEach(appGroups) { group in
                            Label {
                                HStack {
                                    Text(group.appName)
                                        .lineLimit(1)
                                    Spacer()
                                    countPill(group.count, color: .secondary)
                                }
                            } icon: {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: group.id))
                                    .resizable()
                                    .frame(width: 16, height: 16)
                            }
                            .tag(SidebarSelection.appGroup(sourceAppPath: group.id))
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("~/Applications/MultiAI Apps")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("Lưu các file .app độc lập")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    store.openStandaloneAppsFolder()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Mở thư mục MultiAI Apps trong Finder")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Detail

    private var detailContent: some View {
        VStack(spacing: 0) {
            bannersArea

            if store.instances.isEmpty {
                emptyStateView
            } else if filteredInstances.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if showGroupActionBar {
                            groupActionBar
                        }

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 290, maximum: 380), spacing: 14)],
                            spacing: 14
                        ) {
                            ForEach(filteredInstances) { instance in
                                InstanceCardView(
                                    instance: instance,
                                    isRunning: store.isRunning(instance),
                                    pid: store.pid(for: instance),
                                    onLaunch: { store.launch(instance) },
                                    onFocus: { store.focus(instance) },
                                    onStop: { force in store.stop(instance, force: force) },
                                    onEdit: { editingInstance = instance },
                                    onDuplicate: {
                                        do {
                                            try store.duplicateInstance(instance)
                                        } catch {
                                            store.lastErrorMessage = error.localizedDescription
                                        }
                                    },
                                    onRebuildApp: { store.rebuildStandaloneApp(for: instance) },
                                    onRevealApp: { store.revealStandaloneApp(instance) },
                                    onRevealProfile: { store.revealProfileFolder(instance) },
                                    onDelete: { deleteProfileData in
                                        do {
                                            try store.deleteInstance(instance, deleteProfileData: deleteProfileData)
                                        } catch {
                                            store.lastErrorMessage = error.localizedDescription
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    private var showGroupActionBar: Bool {
        filteredInstances.count >= 2
    }

    private var groupActionBar: some View {
        HStack(spacing: 10) {
            Text("\(filteredInstances.count) tài khoản")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                store.launchAll(filteredInstances)
            } label: {
                Label("Mở tất cả", systemImage: "play.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                store.launchAndTile(filteredInstances, layout: .sideBySide)
            } label: {
                Label("Mở & Chia Side-by-Side", systemImage: "rectangle.split.2x1")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            if filteredInstances.contains(where: { store.isRunning($0) }) {
                Button {
                    store.stopAll(filteredInstances)
                } label: {
                    Label("Tắt tất cả", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var bannersArea: some View {
        if let err = store.lastErrorMessage {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(err)
                    .font(.callout)
                Spacer()
                if store.needsAccessibilityBanner {
                    Button("Mở Cài đặt Accessibility") {
                        store.openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Button {
                    store.lastErrorMessage = nil
                    store.needsAccessibilityBanner = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.12))
        } else if let info = store.statusBannerMessage {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(info)
                    .font(.callout)
                Spacer()
                Button {
                    store.statusBannerMessage = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.10))
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ContentUnavailableView {
                Label("Chưa có tài khoản AI nào", systemImage: "square.stack.3d.up.badge.a")
            } description: {
                Text("Thêm tài khoản mới để tạo một phiên bản app độc lập có biểu tượng riêng và chạy song song cùng lúc.")
            } actions: {
                Button {
                    uiState.openAddAccount()
                } label: {
                    Label("Thêm Tài khoản Đầu tiên", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if !quickStartApps.isEmpty {
                VStack(spacing: 10) {
                    Text("Tạo nhanh từ ứng dụng đã cài trên máy")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        ForEach(quickStartApps) { app in
                            Button {
                                let defaultURL = app.detectedEngine == .chromiumBrowserApp ? "https://gemini.google.com" : nil
                                uiState.openAddAccount(app: app, url: defaultURL)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                        .resizable()
                                        .frame(width: 22, height: 22)
                                    Text(app.detectedEngine == .chromiumBrowserApp ? "Gemini (\(app.name))" : app.name)
                                        .font(.callout.weight(.medium))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func countPill(_ count: Int, color: Color) -> some View {
        Text("\(count)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}
