import AppKit
import Foundation

public enum IconBadgeError: Error, LocalizedError {
    case bitmapCreationFailed
    case pngEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .bitmapCreationFailed:
            return "Không thể tạo bitmap để vẽ icon."
        case .pngEncodingFailed:
            return "Không thể mã hoá PNG cho file .icns."
        }
    }
}

/// Renders custom badged app icons and writes valid multi-resolution macOS `.icns` files.
public enum IconBadgeRenderer {
    /// Generates a live SwiftUI/AppKit preview `NSImage` for a configured instance icon.
    public static func renderPreviewImage(
        sourceAppPath: String,
        badgeText: String,
        badgeColor: BadgeColor,
        pixelSize: Int = 128
    ) -> NSImage {
        guard let rep = try? renderBadgedIcon(
            sourceAppPath: sourceAppPath,
            badgeText: badgeText,
            badgeColor: badgeColor,
            pixelSize: pixelSize
        ) else {
            return NSWorkspace.shared.icon(forFile: sourceAppPath)
        }
        let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
        image.addRepresentation(rep)
        return image
    }

    /// Renders an exact-pixel `NSBitmapImageRep` of the source app icon with a colored bottom-right badge.
    public static func renderBadgedIcon(
        sourceAppPath: String,
        badgeText: String,
        badgeColor: BadgeColor,
        pixelSize: Int
    ) throws -> NSBitmapImageRep {
        let rep = try makeBitmapRep(pixelSize: pixelSize)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            throw IconBadgeError.bitmapCreationFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        defer { NSGraphicsContext.restoreGraphicsState() }

        ctx.imageInterpolation = .high

        let size = CGFloat(pixelSize)
        let canvasRect = NSRect(x: 0, y: 0, width: size, height: size)

        NSColor.clear.setFill()
        canvasRect.fill()

        let sourceIcon = NSWorkspace.shared.icon(forFile: sourceAppPath)
        sourceIcon.draw(
            in: canvasRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )

        let cleanText = String(badgeText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2)).uppercased()
        drawBadge(
            in: size,
            text: cleanText,
            color: badgeColor.nsColor
        )

        return rep
    }

    /// Renders the MultiAI manager app's own squircle icon.
    public static func renderMultiAIManagerIcon(pixelSize: Int) throws -> NSBitmapImageRep {
        let rep = try makeBitmapRep(pixelSize: pixelSize)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            throw IconBadgeError.bitmapCreationFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        defer { NSGraphicsContext.restoreGraphicsState() }

        let s = CGFloat(pixelSize)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: s, height: s).fill()

        // Outer macOS icon bounds with standard ~10% inset
        let inset = s * 0.08
        let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let cornerRadius = rect.width * 0.225
        let squircle = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.02)
        shadow.shadowBlurRadius = s * 0.04
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        shadow.set()
        NSColor(srgbRed: 0.10, green: 0.12, blue: 0.26, alpha: 1.0).setFill()
        squircle.fill()
        NSGraphicsContext.restoreGraphicsState()

        squircle.addClip()

        // Rich indigo-to-teal gradient background
        if let gradient = NSGradient(colors: [
            NSColor(srgbRed: 0.22, green: 0.30, blue: 0.92, alpha: 1.0),
            NSColor(srgbRed: 0.42, green: 0.20, blue: 0.85, alpha: 1.0),
            NSColor(srgbRed: 0.08, green: 0.65, blue: 0.82, alpha: 1.0)
        ]) {
            gradient.draw(in: rect, angle: -45)
        }

        // Stacked app-window cards representing simultaneous multi-account apps
        let cardW = rect.width * 0.46
        let cardH = rect.height * 0.46
        let cardRadius = cardW * 0.24

        let backCardRect = NSRect(
            x: rect.minX + rect.width * 0.16,
            y: rect.minY + rect.height * 0.34,
            width: cardW,
            height: cardH
        )
        let backCard = NSBezierPath(roundedRect: backCardRect, xRadius: cardRadius, yRadius: cardRadius)
        NSColor.white.withAlphaComponent(0.32).setFill()
        backCard.fill()
        NSColor.white.withAlphaComponent(0.55).setStroke()
        backCard.lineWidth = max(1.0, s * 0.012)
        backCard.stroke()

        let midCardRect = NSRect(
            x: rect.minX + rect.width * 0.27,
            y: rect.minY + rect.height * 0.26,
            width: cardW,
            height: cardH
        )
        let midCard = NSBezierPath(roundedRect: midCardRect, xRadius: cardRadius, yRadius: cardRadius)
        NSColor.white.withAlphaComponent(0.58).setFill()
        midCard.fill()

        let frontCardRect = NSRect(
            x: rect.minX + rect.width * 0.38,
            y: rect.minY + rect.height * 0.18,
            width: cardW,
            height: cardH
        )
        let frontCard = NSBezierPath(roundedRect: frontCardRect, xRadius: cardRadius, yRadius: cardRadius)
        NSColor.white.withAlphaComponent(0.95).setFill()
        frontCard.fill()

        // Accent dot on front card
        let dotSize = frontCardRect.width * 0.30
        let dotRect = NSRect(
            x: frontCardRect.midX - dotSize * 0.5,
            y: frontCardRect.midY - dotSize * 0.5,
            width: dotSize,
            height: dotSize
        )
        let dotPath = NSBezierPath(ovalIn: dotRect)
        NSColor(srgbRed: 0.22, green: 0.45, blue: 0.96, alpha: 1.0).setFill()
        dotPath.fill()

        return rep
    }

    /// Writes a multi-resolution macOS `.icns` file from a bitmap renderer closure.
    public static func writeICNS(
        to url: URL,
        renderSize: (Int) throws -> NSBitmapImageRep
    ) throws {
        let chunksSpec: [(type: String, size: Int)] = [
            ("ic07", 128),
            ("ic08", 256),
            ("ic09", 512),
            ("ic10", 1024)
        ]

        var body = Data()
        for spec in chunksSpec {
            let rep = try renderSize(spec.size)
            guard let pngData = rep.representation(using: .png, properties: [:]) else {
                throw IconBadgeError.pngEncodingFailed
            }
            guard let typeBytes = spec.type.data(using: .ascii), typeBytes.count == 4 else {
                continue
            }
            body.append(typeBytes)
            var chunkLength = UInt32(8 + pngData.count).bigEndian
            body.append(Data(bytes: &chunkLength, count: 4))
            body.append(pngData)
        }

        var fileData = Data("icns".utf8)
        var totalLength = UInt32(8 + body.count).bigEndian
        fileData.append(Data(bytes: &totalLength, count: 4))
        fileData.append(body)

        try fileData.write(to: url, options: [.atomic])
    }

    // MARK: - Private Drawing Helpers

    private static func makeBitmapRep(pixelSize: Int) throws -> NSBitmapImageRep {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw IconBadgeError.bitmapCreationFailed
        }
        rep.size = NSSize(width: pixelSize, height: pixelSize)
        return rep
    }

    private static func drawBadge(in size: CGFloat, text: String, color: NSColor) {
        let badgeDiameter = size * 0.40
        let margin = size * 0.04
        // In AppKit bitmap contexts (origin at bottom-left), bottom-right is near (size - margin - d, margin).
        let badgeRect = NSRect(
            x: size - margin - badgeDiameter,
            y: margin,
            width: badgeDiameter,
            height: badgeDiameter
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.015)
        shadow.shadowBlurRadius = size * 0.035
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
        shadow.set()

        let badgePath = NSBezierPath(ovalIn: badgeRect)
        color.setFill()
        badgePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Crisp white ring border
        let ringWidth = max(1.5, size * 0.028)
        let ringRect = badgeRect.insetBy(dx: ringWidth * 0.5, dy: ringWidth * 0.5)
        let ringPath = NSBezierPath(ovalIn: ringRect)
        ringPath.lineWidth = ringWidth
        NSColor.white.withAlphaComponent(0.95).setStroke()
        ringPath.stroke()

        guard !text.isEmpty else { return }

        let fontScale: CGFloat = text.count == 1 ? 0.54 : 0.42
        let fontSize = badgeDiameter * fontScale
        let baseFont = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let font: NSFont
        if let roundedDescriptor = baseFont.fontDescriptor.withDesign(.rounded),
           let rounded = NSFont(descriptor: roundedDescriptor, size: fontSize) {
            font = rounded
        } else {
            font = baseFont
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let textBounds = attrString.boundingRect(
            with: badgeRect.size,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let drawOrigin = NSPoint(
            x: badgeRect.midX - textBounds.width * 0.5,
            y: badgeRect.midY - textBounds.height * 0.5 - (fontSize * 0.03)
        )
        attrString.draw(at: drawOrigin)
    }
}
