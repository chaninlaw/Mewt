#if DEBUG
// PROTOTYPE — throwaway. Wayfinder ticket #5 "Prototype: Support & Bug-report UI
// in the popover" (https://github.com/chaninlaw/Mewt/issues/5).
// Lives only on the `prototype/support-ui` branch. Never merge.
//
// Three layouts of Support Mewt + Report a Bug, switchable from the debug bar
// at the bottom of the popover (or ⌥⌘← / ⌥⌘→), crossed with four ways of
// presenting the StoreKit purchase sheet, plus forced UI states.
//
//   A  Section in Settings   — tips as rows inside the Settings page
//   B  Own sub-page          — heart in main footer → Support page with cards
//   C  Dedicated window      — heart opens a small "Support Mewt" NSWindow
//
// Run with `Prototype.storekit` selected (shared scheme does this) so no
// App Store Connect setup is needed. Local StoreKit never touches the
// network, so this says NOTHING about the network.client question (#8).

import AppKit
import StoreKit
import SwiftUI

// MARK: - Knobs

enum ProtoLayout: String, CaseIterable, Identifiable {
    case settingsSection = "A", subPage = "B", window = "C"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .settingsSection: "Section in Settings"
        case .subPage:         "Own sub-page"
        case .window:          "Dedicated window"
        }
    }
}

enum ProtoPurchaseMode: String, CaseIterable, Identifiable {
    case pinnedConfirmIn    = "confirmIn + pin popover"
    case transientConfirmIn = "confirmIn, stay transient"
    case purchaseAction     = "@Environment(\\.purchase)"
    case productView        = "ProductView"
    var id: String { rawValue }
}

enum ProtoForcedState: String, CaseIterable, Identifiable {
    case live, loading, failed, pending, thanks
    var id: String { rawValue }
}

/// AppKit handles the SwiftUI side needs. Set by `TrayController.install`.
@MainActor
enum ProtoHooks {
    static var popover: NSPopover?
    static var popoverWindow: NSWindow? { popover?.contentViewController?.view.window }
}

// MARK: - Store

@MainActor
@Observable
final class ProtoTipStore {
    static let shared = ProtoTipStore()

    static let productIDs = [
        "com.chaninlaw.Mewt.tip.treat",
        "com.chaninlaw.Mewt.tip.tuna",
        "com.chaninlaw.Mewt.tip.tower",
    ]

    enum Phase: Equatable { case loading, failed, ready, purchasing(String), pending, thanks }

    var layout: ProtoLayout = .settingsSection
    var mode: ProtoPurchaseMode = .pinnedConfirmIn
    var forced: ProtoForcedState = .live

    private(set) var products: [Product] = []
    private(set) var phase: Phase = .loading
    /// Thank-you copy stays until the next reload; the mascot reaction
    /// only shows while `phase == .thanks` (~3 s).
    private(set) var thanked = false
    private(set) var log: [String] = []

    private var updatesTask: Task<Void, Never>?

    var effectivePhase: Phase {
        switch forced {
        case .live:    phase
        case .loading: .loading
        case .failed:  .failed
        case .pending: .pending
        case .thanks:  .thanks
        }
    }

    var showsThanksCopy: Bool { thanked || forced == .thanks }

    func note(_ s: String) {
        let behavior = ProtoHooks.popover.map { "\($0.behavior.protoName)" } ?? "-"
        log.insert("\(s)  [popover: \(behavior)]", at: 0)
        log = Array(log.prefix(4))
        print("[proto-tips] \(s)")
    }

    func startListener() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let t) = result else { continue }
                await t.finish()
                self?.celebrate("updates: \(t.productID)")
            }
        }
    }

    func load() async {
        thanked = false
        phase = .loading
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { $0.price < $1.price }
            phase = loaded.isEmpty ? .failed : .ready
            note("loaded \(loaded.count) products")
        } catch {
            phase = .failed
            note("load error: \(error.localizedDescription)")
        }
    }

    /// `window` is where the sheet should anchor: the popover's window for
    /// layouts A/B, the dedicated window for C. `action` is set only in
    /// `.purchaseAction` mode.
    func purchase(_ product: Product, in window: NSWindow?, action: PurchaseAction?) async {
        phase = .purchasing(product.id)
        let popover = ProtoHooks.popover
        let original = popover?.behavior
        let pin = mode == .pinnedConfirmIn && window != nil && window === ProtoHooks.popoverWindow
        if pin { popover?.behavior = .applicationDefined }
        defer { if pin, let original { popover?.behavior = original } }

        note("purchase \(product.displayName) via \(mode.rawValue), window: \(window?.title.nonEmpty ?? (window == nil ? "nil" : "popover"))")
        do {
            let result: Product.PurchaseResult
            if mode == .purchaseAction, let action {
                result = try await action(product)
            } else if let window {
                result = try await product.purchase(confirmIn: window)
            } else {
                result = try await product.purchase()
            }
            await handle(result, for: product)
        } catch {
            phase = .ready
            note("purchase error: \(error.localizedDescription)")
        }
    }

    func handle(_ result: Product.PurchaseResult, for product: Product) async {
        switch result {
        case .success(let verification):
            if case .verified(let t) = verification { await t.finish() }
            celebrate("success: \(product.displayName)")
        case .userCancelled:
            phase = .ready
            note("cancelled (silent)")
        case .pending:
            phase = .pending
            note("pending (Ask to Buy)")
        @unknown default:
            phase = .ready
        }
    }

    private func celebrate(_ s: String) {
        thanked = true
        phase = .thanks
        note(s)
        Task {
            try? await Task.sleep(for: .seconds(3))
            if phase == .thanks { phase = .ready }
        }
    }
}

private extension NSPopover.Behavior {
    var protoName: String {
        switch self {
        case .transient:         "transient"
        case .semitransient:     "semitransient"
        case .applicationDefined: "appDefined"
        @unknown default:        "?"
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Report a Bug (stub — body contents are ticket #6)

enum ProtoBugReport {
    static let email = "chanin.lor@gmail.com"
    static let issuesURL = URL(string: "https://github.com/chaninlaw/Mewt/issues/new")!

    static func openMail() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let body = """
        What happened?


        What did you expect?


        ---
        Mewt \(version) (\(build)) · macOS \(os)
        Nothing was sent automatically — you can edit or delete this.
        """
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = email
        c.queryItems = [
            URLQueryItem(name: "subject", value: "Mewt bug report"),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }

    static func openIssues() { NSWorkspace.shared.open(issuesURL) }
}

// MARK: - Shared pieces

enum ProtoTipStyle { case rows, cards, bigRows }

/// Renders the tip list for whatever phase the store (or the forced
/// state) is in. `hostWindow` resolves lazily because the popover's
/// window only exists once it's on screen.
struct ProtoTipList: View {
    let style: ProtoTipStyle
    let hostWindow: () -> NSWindow?

    @Environment(\.purchase) private var purchaseAction
    private var store: ProtoTipStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch store.effectivePhase {
            case .loading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading tips…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            case .failed:
                Text("Tips are unavailable right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            default:
                tips
                if store.effectivePhase == .pending {
                    Label("Waiting for approval…", systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if store.showsThanksCopy {
                    ThanksBanner(reacting: store.effectivePhase == .thanks)
                }
            }
        }
    }

    @ViewBuilder private var tips: some View {
        if store.mode == .productView, !store.products.isEmpty {
            // StoreKit owns the button + sheet here.
            VStack(spacing: 6) {
                ForEach(store.products, id: \.id) { p in
                    ProductView(p) { Text(TipArt.emoji(p.id)).font(.title2) }
                        .productViewStyle(.compact)
                }
            }
            .onInAppPurchaseCompletion { product, result in
                if case .success(let r) = result { await store.handle(r, for: product) }
                else { store.note("ProductView error") }
            }
        } else {
            switch style {
            case .rows:    VStack(spacing: 4) { ForEach(items) { row($0) } }
            case .bigRows: VStack(spacing: 8) { ForEach(items) { bigRow($0) } }
            case .cards:   HStack(spacing: 8) { ForEach(items) { card($0) } }
            }
        }
    }

    // Fake items when products didn't load but a state is forced, so the
    // layout is still judgeable.
    private var items: [TipItem] {
        if store.products.isEmpty {
            return zip(ProtoTipStore.productIDs, ["Treat", "Tuna Can", "Cat Tower"]).map { id, name in
                TipItem(id: id, name: name, price: "—", product: nil)
            }
        }
        return store.products.map { TipItem(id: $0.id, name: $0.displayName, price: $0.displayPrice, product: $0) }
    }

    private func buy(_ item: TipItem) {
        guard let p = item.product else { store.note("no product (forced state)"); return }
        Task { await store.purchase(p, in: hostWindow(), action: purchaseAction) }
    }

    private func isBusy(_ item: TipItem) -> Bool { store.effectivePhase == .purchasing(item.id) }

    private func row(_ item: TipItem) -> some View {
        HStack(spacing: 8) {
            Text(TipArt.emoji(item.id))
            Text(item.name).font(.callout)
            Spacer()
            Button { buy(item) } label: {
                if isBusy(item) { ProgressView().controlSize(.mini) } else { Text(item.price) }
            }
            .controlSize(.small)
        }
    }

    private func bigRow(_ item: TipItem) -> some View {
        HStack(spacing: 10) {
            Text(TipArt.emoji(item.id)).font(.title)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.headline)
                Text(TipArt.blurb(item.id)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { buy(item) } label: {
                if isBusy(item) { ProgressView().controlSize(.small) } else { Text(item.price).frame(minWidth: 50) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(.quaternary, in: .rect(cornerRadius: 10))
    }

    private func card(_ item: TipItem) -> some View {
        Button { buy(item) } label: {
            VStack(spacing: 6) {
                Text(TipArt.emoji(item.id)).font(.largeTitle)
                Text(item.name).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Group {
                    if isBusy(item) { ProgressView().controlSize(.mini) } else { Text(item.price) }
                }
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.tint.opacity(0.2), in: .capsule)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.quaternary, in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct TipItem: Identifiable {
    let id: String
    let name: String
    let price: String
    let product: Product?
}

private enum TipArt {
    static func emoji(_ id: String) -> String {
        if id.hasSuffix("treat") { return "🐟" }
        if id.hasSuffix("tuna") { return "🥫" }
        return "🏰"
    }
    static func blurb(_ id: String) -> String {
        if id.hasSuffix("treat") { return "A small tip" }
        if id.hasSuffix("tuna") { return "A generous tip" }
        return "A big, kind tip"
    }
}

private struct ThanksBanner: View {
    let reacting: Bool

    var body: some View {
        HStack(spacing: 8) {
            if reacting {
                VectorPoseView(status: .talking, size: 32)
                    .transition(.scale.combined(with: .opacity))
            }
            Text("Thank you! Your tip keeps Mewt going. 💛")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.smooth, value: reacting)
    }
}

struct ProtoBugButtons: View {
    var body: some View {
        HStack {
            Button("Email…") { ProtoBugReport.openMail() }
            Button("GitHub Issues…") { ProtoBugReport.openIssues() }
        }
        .controlSize(.small)
        Text("Opens your mail app or browser. Nothing is sent automatically.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            if let subtitle {
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Variant A / B hooks into the Settings page

/// Appended to the bottom of `SettingsPage`.
struct ProtoSettingsExtras: View {
    private var store: ProtoTipStore { .shared }

    var body: some View {
        switch store.layout {
        case .settingsSection:
            Divider()
            SectionHeader(title: "Support Mewt", subtitle: "Tips unlock nothing — Mewt stays free.")
            ProtoTipList(style: .rows, hostWindow: { ProtoHooks.popoverWindow })
            Divider()
            SectionHeader(title: "Report a Bug", subtitle: nil)
            ProtoBugButtons()
        case .subPage:
            Divider()
            SectionHeader(title: "Report a Bug", subtitle: nil)
            ProtoBugButtons()
        case .window:
            EmptyView()
        }
    }
}

/// Main-page footer heart, shown for B and C.
struct ProtoSupportFooterButton: View {
    let onOpenSupportPage: () -> Void
    private var store: ProtoTipStore { .shared }

    var body: some View {
        if store.layout != .settingsSection {
            Button {
                if store.layout == .window { ProtoSupportWindow.shared.show() } else { onOpenSupportPage() }
            } label: {
                Image(systemName: "heart")
            }
            .help("Support Mewt")
            .accessibilityLabel("Support Mewt")
        }
    }
}

// MARK: - Variant B: own sub-page

struct ProtoSupportPage: View {
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(.quaternary, in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Back")

                Text("Support Mewt").font(.headline)
                Spacer()
            }

            Text("Mewt is free and stays free. If it saves you an awkward \"you're on mute\", a tip helps keep it going.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ProtoTipList(style: .cards, hostWindow: { ProtoHooks.popoverWindow })

            Text("Tips are one-time and unlock nothing.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal:   .move(edge: .trailing).combined(with: .opacity)
        ))
    }
}

// MARK: - Variant C: dedicated window

@MainActor
final class ProtoSupportWindow {
    static let shared = ProtoSupportWindow()
    private(set) var window: NSWindow?

    func show() {
        ProtoHooks.popover?.performClose(nil)
        if window == nil {
            let host = NSHostingController(rootView: ProtoSupportWindowView(hostWindow: { [weak self] in self?.window }))
            host.sizingOptions = .preferredContentSize
            let w = NSWindow(contentViewController: host)
            w.title = "Support Mewt"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        Task { await ProtoTipStore.shared.load() }
    }
}

private struct ProtoSupportWindowView: View {
    let hostWindow: () -> NSWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VectorPoseView(status: .unmuted, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Support Mewt").font(.title2.weight(.semibold))
                    Text("Mewt is free and stays free. Tips are one-time and unlock nothing.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ProtoTipList(style: .bigRows, hostWindow: hostWindow)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Found a bug?").font(.headline)
                ProtoBugButtons()
            }

            ProtoSwitcherBar()
        }
        .padding(20)
        .frame(width: 360)
    }
}

// MARK: - Debug bar (prototype only, obviously not part of the design)

struct ProtoSwitcherBar: View {
    var body: some View {
        @Bindable var store = ProtoTipStore.shared
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Button { cycle(-1) } label: { Image(systemName: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Text("\(store.layout.rawValue) · \(store.layout.name)")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                Button { cycle(1) } label: { Image(systemName: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            }
            HStack(spacing: 4) {
                Picker("Buy", selection: $store.mode) {
                    ForEach(ProtoPurchaseMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("State", selection: $store.forced) {
                    ForEach(ProtoForcedState.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 110)
            }
            .pickerStyle(.menu)
            Text("phase: \(String(describing: store.phase))  forced: \(store.forced.rawValue)")
            ForEach(store.log, id: \.self) { Text($0).lineLimit(2) }
        }
        .font(.system(size: 9, design: .monospaced))
        .controlSize(.mini)
        .padding(6)
        .foregroundStyle(.white)
        .background(.black.opacity(0.85), in: .rect(cornerRadius: 8))
        .environment(\.colorScheme, .dark)
    }

    private func cycle(_ delta: Int) {
        let store = ProtoTipStore.shared
        let all = ProtoLayout.allCases
        let i = all.firstIndex(of: store.layout)!
        store.layout = all[(i + delta + all.count) % all.count]
    }
}
#endif
