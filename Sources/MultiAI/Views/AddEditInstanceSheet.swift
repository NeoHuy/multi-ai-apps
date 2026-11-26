import AppKit
import MultiAICore
import SwiftUI
import UniformTypeIdentifiers

struct AddEditInstanceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let store: InstanceStore
    let editingInstance: AppInstance?
    let initialApp: InstalledApp?
    let initialURL: String?

    @State private var selectedApp: InstalledApp?
    @State private var name: String = ""
    @State private var badgeText: String = "1"
    @State private var badgeColor: BadgeColor = .blue
    @State private var engine: IsolationEngine = .electron
    @State private var targetURL: String = ""
    @State private var isolateExtensions: Bool = false
    @State private var isolateHomeDirectory: Bool = false
    @State private var shareAntigravityProjects: Bool = false
    @State private var extraArgs: String = ""
    @State private var envVars: [EnvVarEntry] = []
    @State private var createStandaloneApp: Bool = true
    @State private var showAdvanced: Bool = false
    @State private var validationError: String?

    init(
        store: InstanceStore,
        editingInstance: AppInstance? = nil,
        initialApp: InstalledApp? = nil,
        initialURL: String? = nil
    ) {
        self.store = store
        self.editingInstance = editingInstance
        self.initialApp = initialApp
        self.initialURL = initialURL
    }

    private var priorityApps: [InstalledApp] {
        let priority = store.installedApps.filter(\.isPriorityAIApp)
        return priority.isEmpty ? Array(store.installedApps.prefix(8)) : priority
    }

    private var availableBrowserForChatGPTFallback: InstalledApp? {
        store.installedApps.first { $0.detectedEngine == .chromiumBrowserApp }
    }

    private var previewSanitizedAppName: String {
        let dummy = AppInstance(
            name: name.isEmpty ? "New Account" : name,
            sourceAppPath: selectedApp?.path ?? "/Applications/Claude.app",
            sourceAppName: selectedApp?.name ?? "App",
            sourceBundleID: selectedApp?.bundleIdentifier ?? "",
            engine: engine,
            badgeText: badgeText,
            badgeColor: badgeColor
        )
        return "\(dummy.sanitizedAppFileName).app"
    }

    private var previewIcon: NSImage {
        let path = selectedApp?.path ?? editingInstance?.sourceAppPath ?? "/Applications"
        return IconBadgeRenderer.renderPreviewImage(
            sourceAppPath: path,
            badgeText: badgeText,
            badgeColor: badgeColor,
            pixelSize: 128
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    appPickerSection
                    identitySection
                    engineBannerSection
                    if engine == .chromiumBrowserApp {
                        browserURLSection
                    }
                    advancedSection
                }
                .padding(20)
            }

            if let validationError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(validationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.08))
            }

            Divider()
            footerBar
        }
        .frame(width: 580, height: 640)
        .onAppear(perform: populateInitialState)
    }

    // MARK: - Sections

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(editingInstance == nil ? "Thêm Tài khoản AI Mới" : "Chỉnh sửa Tài khoản")
                    .font(.headline)
                Text("Tạo một phiên bản app độc lập chạy song song với dữ liệu đăng nhập riêng.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var appPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("1. Chọn Desktop App")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Chọn .app khác...") {
                    browseForApp()
                }
                .controlSize(.small)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(priorityApps) { app in
                        let isSelected = selectedApp?.path == app.path
                        Button {
                            selectApp(app, preserveUserEdits: editingInstance != nil)
                        } label: {
                            VStack(spacing: 6) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                    .resizable()
                                    .frame(width: 36, height: 36)
                                Text(app.name)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text(app.detectedEngine.badgeShortLabel)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 92, height: 84)
                            .padding(.horizontal, 4)
                            .background(
                                isSelected
                                    ? Color.accentColor.opacity(0.14)
                                    : Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                                        lineWidth: isSelected ? 1.5 : 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            if let selectedApp {
                HStack(spacing: 6) {
                    Image(systemName: "app.badge.checkmark")
                        .foregroundStyle(.secondary)
                    Text(selectedApp.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("2. Tên & Biểu tượng App Độc lập")
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 6) {
                    Image(nsImage: previewIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)

                    Text("Xem trước")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tên hiển thị")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Ví dụ: Claude - Công việc", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: name) { _, newValue in
                                if editingInstance == nil {
                                    deriveBadgeIfDefault(from: newValue)
                                }
                            }
                    }

                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nhãn Badge (1-2 ký tự)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("W", text: $badgeText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                .onChange(of: badgeText) { _, newVal in
                                    if newVal.count > 2 {
                                        badgeText = String(newVal.prefix(2))
                                    }
                                }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Màu Badge")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 7) {
                                ForEach(BadgeColor.allCases) { color in
                                    Button {
                                        badgeColor = color
                                    } label: {
                                        Circle()
                                            .fill(color.swiftUIColor)
                                            .frame(width: 20, height: 20)
                                            .overlay {
                                                if badgeColor == color {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .help(color.displayName)
                                }
                            }
                        }
                    }
                }
            }

            Toggle(isOn: $createStandaloneApp) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tạo file .app độc lập trong ~/Applications/MultiAI Apps")
                        .font(.callout)
                    if createStandaloneApp {
                        Text("~/Applications/MultiAI Apps/\(previewSanitizedAppName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var engineBannerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: engine.supportsTrueMultiAccount ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(engine.supportsTrueMultiAccount ? .green : .orange)
                Text("Chế độ tách biệt: \(engine.displayName)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            Text(engine.summaryDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            if selectedApp?.recommendsIsolatedHome == true {
                Divider()

                Toggle("Tách thư mục HOME riêng (cần thiết để tách ~/.gemini)", isOn: $isolateHomeDirectory)
                    .font(.callout.weight(.medium))

                Text("Các thư mục và cấu hình CLI từ ~/ (.config, .claude, .aws, .ssh, .gitconfig, workspace...) sẽ được mirror qua symlink, đồng thời terminal con tự động khôi phục quyền truy cập macOS Keychain cho gh, claude và git trong khi ~/.gemini và ~/Library vẫn được tách riêng cho từng tài khoản.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isolateHomeDirectory {
                    Toggle("Dùng chung danh sách Projects, MCP & Plugins (~/.gemini/config)", isOn: $shareAntigravityProjects)
                        .font(.callout.weight(.medium))

                    Text("Chia sẻ danh sách Projects, MCP và Plugins qua symlink mà vẫn giữ riêng tài khoản đăng nhập (jetski-standalone-oauth-token) và các phiên chat/daemon đang chạy (antigravity/).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if selectedApp?.usesKeychainIsolationCaveat == true {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "key.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.top, 2)
                        Text("Lưu ý Keychain: Antigravity có tích hợp macOS Keychain (authstore). Nếu sau khi tách HOME mà macOS vẫn chia sẻ token đăng nhập OAuth giữa các cửa sổ trong cùng user macOS, bạn có thể cần đăng xuất trong cửa sổ thứ 2 hoặc cân nhắc dùng macOS User riêng.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            if engine == .nativeMacOS && (selectedApp?.usesKeychainIsolationCaveat ?? false) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lưu ý cho app Native dùng macOS Keychain (như ChatGPT.app): Các cửa sổ mở đồng thời có thể dùng chung token đăng nhập từ Keychain của hệ thống. Để dùng 2 tài khoản ChatGPT hoàn toàn tách biệt, bạn nên chạy qua Browser App Mode.")
                        .font(.caption)
                        .foregroundStyle(.primary)

                    if let browser = availableBrowserForChatGPTFallback {
                        Button {
                            switchToChatGPTBrowserApp(using: browser)
                        } label: {
                            Label(
                                "Chuyển sang \(browser.name) App Mode (https://chatgpt.com)",
                                systemImage: "arrow.triangle.swap"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var browserURLSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("URL Web App (tuỳ chọn)")
                .font(.subheadline.weight(.semibold))

            TextField("https://gemini.google.com", text: $targetURL)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 6) {
                Text("Gợi ý:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(WebAppPreset.defaults) { preset in
                    Button(preset.title) {
                        targetURL = preset.url
                        badgeColor = preset.suggestedColor
                        if name.trimmingCharacters(in: .whitespaces).isEmpty || name.contains("Google Chrome") || name.contains("Microsoft Edge") {
                            let browserName = selectedApp?.name ?? "Browser"
                            let count = store.instances.filter { ($0.targetURL ?? "").contains(preset.url) }.count + 1
                            name = "\(preset.title) (\(browserName)) \(count)"
                            badgeText = preset.badgeHint
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showAdvanced.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showAdvanced ? 90 : 0))

                    Text("Tuỳ chọn nâng cao")
                        .font(.subheadline.weight(.medium))

                    Spacer()
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showAdvanced {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Engine tách biệt", selection: $engine) {
                        ForEach(IsolationEngine.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.menu)

                    if engine == .vscodeIDE {
                        Toggle("Tách riêng thư mục Extensions (--extensions-dir)", isOn: $isolateExtensions)
                            .font(.callout)
                    }

                    Toggle("Tách biến môi trường HOME riêng cho profile này", isOn: $isolateHomeDirectory)
                        .font(.callout)
                        .help("Hữu ích cho một số app đọc cấu hình từ $HOME thay vì XDG hoặc --user-data-dir.")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tham số dòng lệnh bổ sung (Extra CLI Args)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("--disable-gpu --lang=vi", text: $extraArgs)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Biến môi trường (Environment Variables)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                envVars.append(EnvVarEntry())
                            } label: {
                                Label("Thêm biến", systemImage: "plus")
                            }
                            .controlSize(.mini)
                        }

                        ForEach($envVars) { $entry in
                            HStack(spacing: 8) {
                                TextField("KEY", text: $entry.key)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                                Text("=")
                                    .foregroundStyle(.secondary)
                                TextField("VALUE", text: $entry.value)
                                    .textFieldStyle(.roundedBorder)
                                Button(role: .destructive) {
                                    envVars.removeAll { $0.id == entry.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var footerBar: some View {
        HStack {
            Button("Huỷ") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(editingInstance == nil ? "Tạo Tài khoản" : "Lưu thay đổi") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedApp == nil && editingInstance == nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func populateInitialState() {
        if let editing = editingInstance {
            selectedApp = store.installedApps.first(where: { $0.path == editing.sourceAppPath })
                ?? AppDiscoveryService.inspectApp(at: editing.sourceAppPath)
            name = editing.name
            badgeText = editing.badgeText
            badgeColor = editing.badgeColor
            engine = editing.engine
            targetURL = editing.targetURL ?? ""
            isolateExtensions = editing.isolateExtensions
            isolateHomeDirectory = editing.isolateHomeDirectory
            shareAntigravityProjects = editing.shareAntigravityProjects
            extraArgs = editing.extraArgs
            envVars = editing.envVars
            createStandaloneApp = editing.createStandaloneApp
            return
        }

        if let initialApp {
            selectApp(initialApp, preserveUserEdits: false)
            if let initialURL {
                targetURL = initialURL
            }
        } else if let first = priorityApps.first {
            selectApp(first, preserveUserEdits: false)
        }
    }

    private func selectApp(_ app: InstalledApp, preserveUserEdits: Bool) {
        selectedApp = app
        if !preserveUserEdits {
            engine = app.detectedEngine
            isolateHomeDirectory = app.recommendsIsolatedHome
            shareAntigravityProjects = app.recommendsIsolatedHome
            name = store.suggestedNextName(for: app)
            badgeText = store.suggestedNextBadge(for: app)
            badgeColor = store.suggestedNextColor(for: app)
            if app.detectedEngine == .chromiumBrowserApp && targetURL.isEmpty {
                targetURL = "https://gemini.google.com"
            }
        }
    }

    private func switchToChatGPTBrowserApp(using browser: InstalledApp) {
        selectedApp = browser
        engine = .chromiumBrowserApp
        targetURL = "https://chatgpt.com"
        let count = store.instances.filter { ($0.targetURL ?? "").contains("chatgpt.com") }.count + 1
        name = "ChatGPT - Account \(count)"
        badgeText = String(count)
        badgeColor = .green
    }

    private func deriveBadgeIfDefault(from title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let lastToken = trimmed.split(separator: " ").last {
            if lastToken.count <= 2 && lastToken.allSatisfy({ $0.isLetter || $0.isNumber }) {
                badgeText = String(lastToken).uppercased()
            } else if let first = lastToken.first, first.isLetter || first.isNumber {
                badgeText = String(first).uppercased()
            }
        }
    }

    private func browseForApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "Chọn ứng dụng"

        if panel.runModal() == .OK, let url = panel.url {
            if let inspected = AppDiscoveryService.inspectApp(at: url.path) {
                selectApp(inspected, preserveUserEdits: false)
            } else {
                validationError = "Không đọc được Info.plist của app đã chọn."
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationError = "Vui lòng nhập tên cho tài khoản."
            return
        }

        let duplicateName = store.instances.contains {
            $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame && $0.id != editingInstance?.id
        }
        if duplicateName {
            validationError = "Tên \"\(trimmedName)\" đã tồn tại. Vui lòng chọn tên khác."
            return
        }

        let sourcePath = selectedApp?.path ?? editingInstance?.sourceAppPath ?? ""
        let sourceName = selectedApp?.name ?? editingInstance?.sourceAppName ?? "App"
        let sourceBundleID = selectedApp?.bundleIdentifier ?? editingInstance?.sourceBundleID ?? ""

        guard !sourcePath.isEmpty else {
            validationError = "Vui lòng chọn ứng dụng gốc."
            return
        }

        let cleanURL = targetURL.trimmingCharacters(in: .whitespacesAndNewlines)

        let instance = AppInstance(
            id: editingInstance?.id ?? UUID(),
            name: trimmedName,
            sourceAppPath: sourcePath,
            sourceAppName: sourceName,
            sourceBundleID: sourceBundleID,
            engine: engine,
            badgeText: badgeText.trimmingCharacters(in: .whitespacesAndNewlines),
            badgeColor: badgeColor,
            targetURL: engine == .chromiumBrowserApp && !cleanURL.isEmpty ? cleanURL : nil,
            isolateExtensions: isolateExtensions,
            isolateHomeDirectory: isolateHomeDirectory,
            shareAntigravityProjects: isolateHomeDirectory && shareAntigravityProjects,
            extraArgs: extraArgs,
            envVars: envVars.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty },
            createStandaloneApp: createStandaloneApp,
            standaloneAppPath: editingInstance?.standaloneAppPath,
            createdAt: editingInstance?.createdAt ?? Date(),
            lastLaunchedAt: editingInstance?.lastLaunchedAt
        )

        do {
            if editingInstance == nil {
                try store.addInstance(instance)
            } else {
                try store.updateInstance(instance)
            }
            dismiss()
        } catch {
            validationError = "Lỗi khi lưu: \(error.localizedDescription)"
        }
    }
}
