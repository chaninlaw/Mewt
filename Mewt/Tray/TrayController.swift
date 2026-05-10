import AppKit
import Observation
import SwiftUI

/// Owns the menu-bar `NSStatusItem` and the popover that previously came
/// from SwiftUI's `MenuBarExtra`. We migrated off `MenuBarExtra` because
/// it does not surface right-click events separately from left-click —
/// and Phase 2 needs right-click as a quick mute toggle.
///
/// Click routing lives in `TrayClickRouter` (pure, unit-tested). This
/// controller is the AppKit glue: it reads `NSApp.currentEvent`, maps to
/// a `TrayClickRouter.Click`, and forwards.
@MainActor
final class TrayController {
    private let appState: AppState
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    /// Drives the 12-frame animations (talking / push-to-talk) by
    /// swapping the status item's image once per tick. `nil` whenever
    /// the current status is static.
    private var animationTimer: Timer?
    private var animationFrameIndex: Int = 0

    /// 12fps × 12 frames = ~1s cycle, matching `VectorPoseView` so
    /// the popover and menu-bar mascots stay loosely in step.
    private static let animationFps: Double = 12
    private static let animationFrameCount = 12

    init(appState: AppState) {
        self.appState = appState
    }

    deinit {
        animationTimer?.invalidate()
    }

    /// Creates the status item, wires the button's click handler, mounts
    /// `ContentView` into the popover, and starts observing
    /// `appState.status` so the menu-bar symbol stays in sync.
    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        // Drive popover sizing from the hosting controller's preferred
        // content size, not by pre-setting `popover.contentSize`. The
        // pre-set + hosting-controller combo triggers AppKit's recursive
        // layout warning on first launch ("It's not legal to call
        // -layoutSubtreeIfNeeded on a view which is already being laid
        // out"): the popover schedules a layout against the placeholder
        // size, then the hosting controller asks SwiftUI for its preferred
        // size mid-pass and re-enters layout. `.preferredContentSize`
        // makes the hosting controller publish ideal-size changes through
        // the proper AppKit channels, breaking the cycle.
        let host = NSHostingController(
            rootView: ContentView().environment(appState)
        )
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host

        updateButton()
        observeStatus()
    }

    @objc private func handleClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        let click: TrayClickRouter.Click
        switch event.type {
        case .rightMouseUp:
            click = .right
        case .leftMouseUp:
            click = event.modifierFlags.contains(.control) ? .leftWithControl : .left
        default:
            return
        }
        TrayClickRouter.route(
            click,
            onTogglePopover: { [weak self] in self?.togglePopover() },
            onToggleMute: { [weak self] in self?.appState.toggleMute() }
        )
    }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Activate so the popover takes focus instead of staying behind
            // the previously-active app.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// `withObservationTracking` is single-fire: re-subscribe inside
    /// `onChange` so we keep getting updates as long as the controller
    /// lives.
    private func observeStatus() {
        withObservationTracking { [weak self] in
            _ = self?.appState.status
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateButton()
                self.observeStatus()
            }
        }
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }
        let status = appState.status

        // Cancel any in-flight animation. updateButton is the single
        // funnel for both static and animated rendering, so here is
        // the right place to tear the old timer down before committing
        // to whichever path the new status needs.
        animationTimer?.invalidate()
        animationTimer = nil

        switch status {
        case .talking:
            startAnimation(button: button, framePrefix: "talk", tint: nil, label: status.label)
        case .pushToTalk:
            // Same `talk` frames as plain talking — accent tint is the
            // only differentiator, which is enough at 18pt menu-bar size.
            startAnimation(button: button, framePrefix: "talk", tint: .controlAccentColor, label: status.label)
        default:
            renderStatic(button: button, status: status)
        }
        button.toolTip = "\(status.label) — left-click to open, right-click to toggle mute"
    }

    /// Draws the cat + state badge as a single template image. Used
    /// for every state except `.talking`, which animates separately.
    private func renderStatic(button: NSStatusBarButton, status: MicStatus) {
        let image = Self.composeMenuBarImage(
            main: status.menuBarMainSymbol,
            badge: status.menuBarBadgeSymbol,
            accessibilityDescription: status.label
        )
        image?.isTemplate = true
        button.contentTintColor = nil
        button.image = image
    }

    /// Starts a repeating timer that swaps the status-item image
    /// through `<framePrefix>-1` … `<framePrefix>-12` on every tick.
    /// `tint` is applied to the button; `nil` means use the system
    /// default (template glyph in menu-bar text color). The first
    /// frame renders synchronously so the bar doesn't flash the
    /// previous state's icon while waiting for the timer to fire.
    private func startAnimation(
        button: NSStatusBarButton,
        framePrefix: String,
        tint: NSColor?,
        label: String
    ) {
        animationFrameIndex = 0
        renderAnimationFrame(button: button, framePrefix: framePrefix, tint: tint, label: label)
        animationTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / Self.animationFps,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let button = self.statusItem?.button else { return }
                self.animationFrameIndex = (self.animationFrameIndex + 1) % Self.animationFrameCount
                self.renderAnimationFrame(button: button, framePrefix: framePrefix, tint: tint, label: label)
            }
        }
    }

    private func renderAnimationFrame(
        button: NSStatusBarButton,
        framePrefix: String,
        tint: NSColor?,
        label: String
    ) {
        // The animation conveys itself through the cycling glyph; no
        // extra badge is composited on top so the silhouette stays
        // legible at 18pt menu-bar size.
        let mainName = "\(framePrefix)-\(animationFrameIndex + 1)"
        let baseImage = Self.composeMenuBarImage(
            main: mainName,
            badge: nil,
            accessibilityDescription: label
        )
        // Template images on the menu bar are tinted by the system
        // to match menu-bar text color and *ignore* `contentTintColor`,
        // which means PTT's accent never showed up. For tinted states
        // we bake the color into a non-template image; untinted states
        // stay templated so they continue to flip with light/dark mode.
        if let tint, let baseImage {
            let tinted = Self.tinted(baseImage, with: tint, label: label)
            tinted.isTemplate = false
            button.contentTintColor = nil
            button.image = tinted
        } else {
            baseImage?.isTemplate = true
            button.contentTintColor = nil
            button.image = baseImage
        }
    }

    /// Returns a non-template copy of `image` whose opaque pixels are
    /// filled with `color`. Used for menu-bar states that need a
    /// custom color (e.g. PTT's accent tint) — see `renderAnimationFrame`.
    @MainActor
    private static func tinted(_ image: NSImage, with color: NSColor, label: String) -> NSImage {
        let size = image.size
        let tinted = NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceIn)
            return true
        }
        tinted.accessibilityDescription = label
        return tinted
    }

    /// Standard menu-bar icon point size (Apple HIG ~18pt for status
    /// bar items). Used to size both main glyph and badge.
    private static let menuBarPointSize: CGFloat = 18

    /// Builds a single template `NSImage` stacking the cat asset (full
    /// canvas) with an optional SF-Symbol `badge` (~55% scale, bold)
    /// in the bottom-right corner. `main` is an asset-catalog image
    /// name resolved via `NSImage(named:)`; `badge` is an SF Symbol
    /// resolved via `NSImage(systemSymbolName:)`. Returns `nil` only
    /// when the main asset can't be loaded.
    ///
    /// Both branches (with/without badge) wrap the result in the
    /// same drawingHandler-backed `NSImage` so AppKit measures the
    /// composite by a stable canvas size. Returning the bare main
    /// image for no-badge states caused the menu-bar item to shift
    /// width when state changed: AppKit measures rep-backed images
    /// differently from drawingHandler-backed ones, so neighbours
    /// in the bar reflowed every transition.
    @MainActor
    private static func composeMenuBarImage(
        main: String,
        badge: String?,
        accessibilityDescription: String
    ) -> NSImage? {
        guard let mainImg = NSImage(named: main) else { return nil }
        let canvas = NSSize(width: menuBarPointSize, height: menuBarPointSize)
        // Mutate to the canvas size so `mainImg.draw(in:)` fills the
        // composite cleanly. Asset-catalog vector images keep their
        // SVG-derived natural size (24pt) by default, which would
        // leave whitespace around the cat at 18pt menu-bar size.
        mainImg.size = canvas

        // Badge resolves as asset-catalog image first (e.g.
        // `paw-print`) then falls back to SF Symbol. Asset images
        // are sized via `.size = …`; SF Symbols size via
        // `withSymbolConfiguration`. Both end up at ~55% of canvas.
        let badgeSize = menuBarPointSize * 0.55
        let badgeImg: NSImage? = badge.flatMap { name -> NSImage? in
            if let assetImg = NSImage(named: name) {
                assetImg.size = NSSize(width: badgeSize, height: badgeSize)
                return assetImg
            }
            let badgeCfg = NSImage.SymbolConfiguration(
                pointSize: badgeSize,
                weight: .bold
            )
            return NSImage(
                systemSymbolName: name,
                accessibilityDescription: nil
            )?.withSymbolConfiguration(badgeCfg)
        }

        let composite = NSImage(size: canvas, flipped: false) { _ in
            mainImg.draw(in: NSRect(origin: .zero, size: canvas))
            if let bi = badgeImg {
                let bs = bi.size
                let inset: CGFloat = 0.5
                let badgeRect = NSRect(
                    x: canvas.width - bs.width - inset,
                    y: inset,
                    width: bs.width,
                    height: bs.height
                )
                // Knock a circular hole in the cat under the badge so
                // the badge sits on a clean transparent island. Without
                // this, template tinting renders cat + badge in the
                // same color and the badge's shape bleeds into the cat
                // silhouette — illegible at 18pt menu-bar size. The
                // `.clear` compositing op replaces destination alpha
                // with 0 inside the filled ellipse.
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .clear
                let knockoutPad: CGFloat = 0.5
                let knockoutRect = badgeRect.insetBy(dx: -knockoutPad, dy: -knockoutPad)
                NSBezierPath(ovalIn: knockoutRect).fill()
                NSGraphicsContext.restoreGraphicsState()

                bi.draw(in: badgeRect)
            }
            return true
        }
        composite.accessibilityDescription = accessibilityDescription
        return composite
    }
}
