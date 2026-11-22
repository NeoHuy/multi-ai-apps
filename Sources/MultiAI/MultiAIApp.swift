import AppKit
import Foundation
import MultiAICore
import SwiftUI

@main
enum MultiAIEntryPoint {
    static func main() {
        let args = CommandLine.arguments
        if let flagIdx = args.firstIndex(of: "--generate-manager-icon"),
           flagIdx + 1 < args.count {
            let outputPath = args[flagIdx + 1]
            let outputURL = URL(fileURLWithPath: outputPath)
            do {
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try IconBadgeRenderer.writeICNS(to: outputURL) { size in
                    try IconBadgeRenderer.renderMultiAIManagerIcon(pixelSize: size)
                }
                Foundation.exit(0)
            } catch {
                fputs("Failed to generate manager icon: \(error.localizedDescription)\n", stderr)
                Foundation.exit(1)
            }
        }

        MultiAIApp.main()
    }
}

struct MultiAIApp: App {
    @State private var store = InstanceStore()
    @State private var uiState = AppUIState()

    var body: some Scene {
        Window("MultiAI", id: "dashboard") {
            DashboardView(store: store, uiState: uiState)
        }
        .defaultSize(width: 980, height: 660)
        .windowToolbarStyle(.unified)

        MenuBarExtra("MultiAI", systemImage: "square.stack.3d.up.fill") {
            MenuBarView(store: store, uiState: uiState)
        }
        .menuBarExtraStyle(.window)
    }
}
