import AppKit
import ApplicationServices
import Foundation

/// Outcome of an Accessibility window-tiling request.
public enum TileResult: Equatable, Sendable {
    case success(tiledCount: Int)
    case needsAccessibilityPermission
    case noWindowsFound
}

/// Computes non-overlapping window frames and arranges running app windows via macOS Accessibility APIs.
public enum WindowTiler {
    /// Checks whether the app holds Accessibility permission, optionally prompting macOS System Settings.
    public static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Computes Quartz/AX top-left coordinates for `count` windows inside an AppKit `visibleFrame`.
    public static func computeFrames(
        count: Int,
        in visibleFrame: CGRect,
        primaryScreenHeight: CGFloat,
        layout: WindowTileLayout,
        gap: CGFloat = 6
    ) -> [CGRect] {
        guard count > 0 else { return [] }

        let topY = primaryScreenHeight - visibleFrame.maxY
        let leftX = visibleFrame.minX
        let totalW = visibleFrame.width
        let totalH = visibleFrame.height

        switch layout {
        case .sideBySide:
            let itemW = floor((totalW - gap * CGFloat(count - 1)) / CGFloat(count))
            return (0..<count).map { idx in
                let x = leftX + CGFloat(idx) * (itemW + gap)
                let width = (idx == count - 1) ? (leftX + totalW - x) : itemW
                return CGRect(x: x, y: topY, width: max(100, width), height: max(100, totalH))
            }

        case .stacked:
            let itemH = floor((totalH - gap * CGFloat(count - 1)) / CGFloat(count))
            return (0..<count).map { idx in
                let y = topY + CGFloat(idx) * (itemH + gap)
                let height = (idx == count - 1) ? (topY + totalH - y) : itemH
                return CGRect(x: leftX, y: y, width: max(100, totalW), height: max(100, height))
            }

        case .grid:
            if count == 1 {
                return [CGRect(x: leftX, y: topY, width: totalW, height: totalH)]
            }
            let cols = Int(ceil(sqrt(Double(count))))
            let rows = Int(ceil(Double(count) / Double(cols)))
            let rowH = floor((totalH - gap * CGFloat(rows - 1)) / CGFloat(rows))

            var frames: [CGRect] = []
            frames.reserveCapacity(count)

            for r in 0..<rows {
                let startIdx = r * cols
                let itemsInRow = min(cols, count - startIdx)
                let colW = floor((totalW - gap * CGFloat(itemsInRow - 1)) / CGFloat(itemsInRow))
                let y = topY + CGFloat(r) * (rowH + gap)
                let h = (r == rows - 1) ? (topY + totalH - y) : rowH

                for c in 0..<itemsInRow {
                    let x = leftX + CGFloat(c) * (colW + gap)
                    let w = (c == itemsInRow - 1) ? (leftX + totalW - x) : colW
                    frames.append(CGRect(x: x, y: y, width: max(100, w), height: max(100, h)))
                }
            }
            return frames
        }
    }

    /// Tiles the main windows of the specified running PIDs using the requested layout.
    @MainActor
    public static func tileWindows(pids: [pid_t], layout: WindowTileLayout) -> TileResult {
        guard !pids.isEmpty else { return .noWindowsFound }

        if !isAccessibilityTrusted(prompt: true) {
            return .needsAccessibilityPermission
        }

        let targetScreen = NSScreen.main ?? NSScreen.screens.first
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? targetScreen?.frame.height ?? 900
        let visibleFrame = targetScreen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 875)

        let frames = computeFrames(
            count: pids.count,
            in: visibleFrame,
            primaryScreenHeight: primaryScreenHeight,
            layout: layout
        )

        var tiledCount = 0

        for (pid, frame) in zip(pids, frames) {
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.activate(options: [.activateAllWindows])
            }
            if setPrimaryWindowFrame(for: pid, frame: frame) {
                tiledCount += 1
            }
        }

        return tiledCount > 0 ? .success(tiledCount: tiledCount) : .noWindowsFound
    }

    private static func setPrimaryWindowFrame(for pid: pid_t, frame: CGRect) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        guard let window = findTargetWindow(for: appElement) else {
            return false
        }

        var origin = frame.origin
        var size = frame.size

        guard let posVal1 = AXValueCreate(.cgPoint, &origin),
              let sizeVal = AXValueCreate(.cgSize, &size),
              let posVal2 = AXValueCreate(.cgPoint, &origin) else {
            return false
        }

        let r1 = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal1)
        let r2 = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        let r3 = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal2)

        return r1 == .success || r2 == .success || r3 == .success
    }

    private static func findTargetWindow(for appElement: AXUIElement) -> AXUIElement? {
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        if err == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty {
            for win in windows {
                var subroleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(win, kAXSubroleAttribute as CFString, &subroleRef) == .success,
                   let subrole = subroleRef as? String,
                   subrole == (kAXStandardWindowSubrole as String) {
                    return win
                }
            }
            return windows.first
        }

        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let focused = focusedRef {
            return (focused as! AXUIElement)
        }

        return nil
    }
}
