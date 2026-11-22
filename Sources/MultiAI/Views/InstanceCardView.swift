import AppKit
import MultiAICore
import SwiftUI

struct InstanceCardView: View {
    let instance: AppInstance
    let isRunning: Bool
    let pid: pid_t?
    let onLaunch: () -> Void
    let onFocus: () -> Void
    let onStop: (Bool) -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onRebuildApp: () -> Void
    let onRevealApp: () -> Void
    let onRevealProfile: () -> Void
    let onDelete: (_ deleteProfileData: Bool) -> Void

    @State private var showingDeleteConfirm = false
    @State private var isHovered = false

    private var iconImage: NSImage {
        IconBadgeRenderer.renderPreviewImage(
            sourceAppPath: instance.sourceAppPath,
            badgeText: instance.normalizedBadgeText,
            badgeColor: instance.badgeColor,
            pixelSize: 128
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: iconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.14), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(instance.name)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(instance.sourceAppName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(instance.engine.badgeShortLabel)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(instance.badgeColor.swiftUIColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(instance.badgeColor.swiftUIColor)
                    }

                    if let host = instance.targetURLHost {
                        Label(host, systemImage: "globe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if instance.sourceBundleID.lowercased().hasPrefix("com.google.antigravity") && !instance.isolateHomeDirectory {
                        Label("Chung HOME — bật tách HOME", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                            .foregroundStyle(.orange)
                            .help("Antigravity lưu cấu hình/tài khoản trong ~/.gemini. Hãy bấm Chỉnh sửa và bật 'Tách thư mục HOME riêng'.")
                    }
                }

                Spacer(minLength: 4)

                Menu {
                    cardMenuItems
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24, height: 24)
            }

            Divider()

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isRunning ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)

                    Text(isRunning ? "Đang chạy" : "Đã tắt")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isRunning ? Color.primary : Color.secondary)
                        .help(pid.map { "PID: \($0)" } ?? "Chưa chạy")
                }

                Spacer()

                if isRunning {
                    Button {
                        onFocus()
                    } label: {
                        Label("Focus", systemImage: "macwindow.on.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        onStop(false)
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button {
                        onLaunch()
                    } label: {
                        Label("Launch", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(instance.badgeColor.swiftUIColor)
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isRunning
                        ? Color.green.opacity(0.55)
                        : (isHovered ? Color.primary.opacity(0.18) : Color.primary.opacity(0.08)),
                    lineWidth: isRunning ? 1.5 : 1
                )
        }
        .shadow(color: .black.opacity(isHovered ? 0.10 : 0.04), radius: isHovered ? 8 : 4, y: 2)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            cardMenuItems
        }
        .confirmationDialog(
            "Xoá tài khoản \"\(instance.name)\"?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Chỉ xoá .app & cấu hình (giữ dữ liệu đăng nhập)") {
                onDelete(false)
            }
            Button("Xoá hoàn toàn cả dữ liệu Profile", role: .destructive) {
                onDelete(true)
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Nếu giữ dữ liệu Profile, bạn có thể tạo lại tài khoản sau mà không mất phiên đăng nhập.")
        }
    }

    @ViewBuilder
    private var cardMenuItems: some View {
        if isRunning {
            Button("Focus Window", systemImage: "macwindow.on.rectangle", action: onFocus)
            Button("Stop App", systemImage: "stop.circle") { onStop(false) }
            Button("Force Quit", systemImage: "xmark.octagon") { onStop(true) }
            Divider()
        } else {
            Button("Launch", systemImage: "play.circle", action: onLaunch)
            Divider()
        }

        Button("Chỉnh sửa...", systemImage: "pencil", action: onEdit)
        Button("Nhân bản (tạo thêm tài khoản)", systemImage: "plus.square.on.square", action: onDuplicate)
        Divider()
        Button("Hiện file .app trong Finder", systemImage: "folder", action: onRevealApp)
        Button("Mở thư mục Profile", systemImage: "internaldrive", action: onRevealProfile)
        Button("Tạo lại file .app", systemImage: "arrow.triangle.2.circlepath", action: onRebuildApp)
        Divider()
        Button("Xoá...", systemImage: "trash", role: .destructive) {
            showingDeleteConfirm = true
        }
    }
}
