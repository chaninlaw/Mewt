import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders a SwiftUI view offscreen into an App Store–ready PNG:
/// 2880×1800 (960×600 pt at 3x), sRGB, no alpha.
@MainActor
enum ScreenshotRenderer {
    static let canvas = CGSize(width: 960, height: 600)
    static let scale: CGFloat = 3

    struct RenderError: Error, CustomStringConvertible {
        let description: String
    }

    static func png(of view: some View) async throws -> Data {
        let host = NSHostingView(rootView: view.frame(width: canvas.width, height: canvas.height))
        host.frame = CGRect(origin: .zero, size: canvas)
        // Key + active, parked off-screen: inactive windows draw
        // prominent buttons grey instead of in the accent colour.
        let window = KeyableWindow(
            contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: canvas),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKey()
        host.layoutSubtreeIfNeeded()
        // Let `.task` modifiers (tip loading) and the first layout pass run.
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        host.display()

        let pixelsWide = Int(canvas.width * scale)
        let pixelsHigh = Int(canvas.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw RenderError(description: "bitmap alloc failed") }
        rep.size = canvas
        host.cacheDisplay(in: host.bounds, to: rep)
        window.close()

        guard let source = rep.cgImage else { throw RenderError(description: "no CGImage") }
        return try flattenedPNG(source, width: pixelsWide, height: pixelsHigh)
    }

    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    /// Redraws onto an opaque sRGB context so the PNG has no alpha channel.
    private static func flattenedPNG(_ image: CGImage, width: Int, height: Int) throws -> Data {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: srgb,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { throw RenderError(description: "context alloc failed") }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let flat = ctx.makeImage() else { throw RenderError(description: "flatten failed") }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw RenderError(description: "PNG encoder unavailable")
        }
        CGImageDestinationAddImage(dest, flat, [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw RenderError(description: "PNG encode failed") }
        return data as Data
    }
}
