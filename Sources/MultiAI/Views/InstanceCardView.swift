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
                        Label("Shared HOME — enable HOME isolation", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                            .foregroundStyle(.orange)
                            .help("Antigravity stores configuration and accounts in ~/.gemini. Click Edit and enable 'Isolate HOME directory'.")
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
                .menuIndicator(.hidden)
                .frame(width: 24, height: 24)
            }

            Divider()

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isRunning ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)

                    Text(isRunning ? "Running" : "Stopped")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isRunning ? Color.primary : Color.secondary)
                        .help(pid.map { "PID: \($0)" } ?? "Not running")
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
            "Delete account \"\(instance.name)\"?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove .app & Config Only (Keep Login Data)") {
                onDelete(false)
            }
            Button("Delete Everything Including Profile Data", role: .destructive) {
                onDelete(true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("If you keep profile data, you can recreate this account later without losing its login session.")
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

        Button("Edit...", systemImage: "pencil", action: onEdit)
        Button("Duplicate (Create Another Account)", systemImage: "plus.square.on.square", action: onDuplicate)
        Divider()
        Button("Reveal .app in Finder", systemImage: "folder", action: onRevealApp)
        Button("Open Profile Folder", systemImage: "internaldrive", action: onRevealProfile)
        Button("Rebuild .app Bundle", systemImage: "arrow.triangle.2.circlepath", action: onRebuildApp)
        Divider()
        Button("Delete...", systemImage: "trash", role: .destructive) {
            showingDeleteConfirm = true
        }
    }
}
