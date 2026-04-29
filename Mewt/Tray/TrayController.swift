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

    init(appState: AppState) {
        self.appState = appState
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
        // Resolve the symbol; fall back to mic.fill if the requested one
        // doesn't exist on this macOS version so the menu bar never goes
        // blank. `isTemplate = true` is required for `contentTintColor`
        // to apply — without it the button keeps the symbol's native
        // color and any tint we set is silently ignored.
        let image = NSImage(
            systemSymbolName: status.menuBarSymbol,
            accessibilityDescription: status.label
        ) ?? NSImage(
            systemSymbolName: "mic.fill",
            accessibilityDescription: status.label
        )
        image?.isTemplate = true
        // Tint alarm state red so the user spots talking-while-muted at
        // a glance from across the screen.
        if status == .talkingWhileMuted {
            button.contentTintColor = .systemRed
        } else {
            button.contentTintColor = nil
        }
        button.image = image
        button.toolTip = "\(status.label) — left-click to open, right-click to toggle mute"
    }
}
