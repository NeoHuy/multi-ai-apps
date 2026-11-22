import AppKit
import MultiAICore
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    @Bindable var store: InstanceStore
    @Bindable var uiState: AppUIState

    private var sortedInstances: [AppInstance] {
        store.instances.sorted { lhs, rhs in
            let lRun = store.isRunning(lhs)
            let rRun = store.isRunning(rhs)
            if lRun != rRun { return lRun && !rRun }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.runningInstances.count >= 2 {
                quickTileBar
                Divider()
            }

            if sortedInstances.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Chưa có tài khoản nào")
                        .font(.callout.weight(.medium))
                    Text("Mở MultiAI Manager để tạo app đầu tiên.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(sortedInstances) { instance in
                            menuBarRow(instance)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 340)
            }

            Divider()
            footer
        }
        .frame(width: 330)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Text("MultiAI")
                    .font(.headline)

                let count = store.runningInstances.count
                if count > 0 {
                    Text("\(count) đang chạy")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.16), in: Capsule())
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            Button("Mở Manager") {
                openDashboard()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var quickTileBar: some View {
        HStack(spacing: 8) {
            Text("Chia cửa sổ:")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                store.tileRunning(layout: .sideBySide)
                dismiss()
            } label: {
                Label("Side by Side", systemImage: WindowTileLayout.sideBySide.systemImage)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            Button {
                store.tileRunning(layout: .grid)
                dismiss()
            } label: {
                Label("Grid", systemImage: WindowTileLayout.grid.systemImage)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func menuBarRow(_ instance: AppInstance) -> some View {
        let running = store.isRunning(instance)
        let icon = IconBadgeRenderer.renderPreviewImage(
            sourceAppPath: instance.sourceAppPath,
            badgeText: instance.normalizedBadgeText,
            badgeColor: instance.badgeColor,
            pixelSize: 64
        )

        return HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(running ? Color.green : Color.secondary.opacity(0.35))
                        .frame(width: 6, height: 6)
                    Text(instance.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                }

                Text(instance.sourceAppName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if running {
                Button {
                    store.focus(instance)
                    dismiss()
                } label: {
                    Image(systemName: "macwindow.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .help("Focus Window")

                Button {
                    store.stop(instance)
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Stop")
            } else {
                Button {
                    store.launch(instance)
                    dismiss()
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Launch")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            Button {
                openDashboard()
                uiState.openAddAccount()
            } label: {
                Label("Thêm Tài khoản", systemImage: "plus")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button("Thoát MultiAI") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func openDashboard() {
        dismiss()
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }
}
