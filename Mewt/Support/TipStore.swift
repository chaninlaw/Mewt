import AppKit
import Observation
import os

/// One tip as the UI sees it. A plain value type instead of StoreKit's
/// `Product` (which has no public initializer) so `TipStore` can be
/// unit-tested against a mock backend.
struct TipProduct: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let displayPrice: String
    let price: Decimal
}

enum TipPurchaseOutcome: Equatable, Sendable {
    case success
    case userCancelled
    /// Ask to Buy / SCA: approval arrives later via `transactionUpdates()`.
    case pending
}

/// The StoreKit seam. `StoreKitTipBackend` is the real one; tests inject
/// a mock.
@MainActor
protocol TipStoreBackend: AnyObject {
    func loadProducts(ids: [String]) async throws -> [TipProduct]
    /// Runs the purchase and finishes the transaction on success.
    /// `window` anchors the system sheet; `nil` falls back to the key window.
    func purchase(productID: String, confirmIn window: NSWindow?) async throws -> TipPurchaseOutcome
    /// Product IDs of verified transactions delivered outside a direct
    /// purchase call (approved Ask to Buy, unfinished transactions from a
    /// previous launch). Already finished by the backend.
    func transactionUpdates() -> AsyncStream<String>
}

enum TipStorePhase: Equatable {
    case idle
    case loading
    case ready
    /// Products couldn't be fetched (offline, App Store unavailable).
    case failed
    case purchasing(String)
    case pending
}

/// Drives the Support Mewt page: loads the three consumable tips and runs
/// purchases. Stateless by design — nothing about past tips is stored.
@Observable
@MainActor
final class TipStore {
    static let productIDs: [String] = [
        "com.chaninlaw.Mewt.tip.treat",
        "com.chaninlaw.Mewt.tip.tuna",
        "com.chaninlaw.Mewt.tip.tower",
    ]

    private(set) var products: [TipProduct] = []
    private(set) var phase: TipStorePhase = .idle
    /// Thank-you line under the cards. Stays until the page is left.
    private(set) var showsThankYou = false
    /// Short mascot reaction after a tip (~3 s).
    private(set) var isCelebrating = false
    /// Last purchase threw (network, App Store error). Cancels are silent.
    private(set) var purchaseFailed = false

    /// Window the purchase sheet attaches to. Set by `TrayController` to
    /// the popover's window.
    @ObservationIgnored var presentationWindow: () -> NSWindow? = { nil }
    /// Keeps the transient popover open while the system sheet / Apple
    /// Account prompt has focus. Set by `TrayController`.
    @ObservationIgnored var setPopoverPinned: (Bool) -> Void = { _ in }

    @ObservationIgnored private let backend: any TipStoreBackend
    @ObservationIgnored private let celebrationDuration: Duration
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var celebrationTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.chaninlaw.Mewt", category: "TipStore")

    init(backend: any TipStoreBackend, celebrationDuration: Duration = .seconds(3)) {
        self.backend = backend
        self.celebrationDuration = celebrationDuration
    }

    var isPurchasing: Bool {
        if case .purchasing = phase { return true }
        return false
    }

    /// Fetches products unless they're already loaded or in flight. A
    /// previous failure is retried, so opening the page again recovers.
    func loadProductsIfNeeded() async {
        switch phase {
        case .idle, .failed: break
        case .ready where products.isEmpty: break
        default: return
        }
        phase = .loading
        do {
            let loaded = try await backend.loadProducts(ids: Self.productIDs)
            products = loaded.sorted { $0.price < $1.price }
            phase = loaded.isEmpty ? .failed : .ready
        } catch {
            log.error("Tip products failed to load: \(error.localizedDescription, privacy: .public)")
            products = []
            phase = .failed
        }
    }

    func purchase(_ product: TipProduct) async {
        switch phase {
        case .ready, .pending: break
        default: return
        }
        phase = .purchasing(product.id)
        purchaseFailed = false
        setPopoverPinned(true)
        defer { setPopoverPinned(false) }

        do {
            let outcome = try await backend.purchase(productID: product.id, confirmIn: presentationWindow())
            switch outcome {
            case .success:
                phase = .ready
                celebrate()
            case .userCancelled:
                phase = .ready
            case .pending:
                phase = .pending
            }
        } catch {
            log.error("Tip purchase failed: \(error.localizedDescription, privacy: .public)")
            phase = .ready
            purchaseFailed = true
        }
    }

    /// Call once at launch. Catches Ask to Buy approvals and transactions
    /// left unfinished by a previous run.
    func startUpdatesListener() {
        guard updatesTask == nil else { return }
        let updates = backend.transactionUpdates()
        updatesTask = Task { [weak self] in
            for await productID in updates {
                guard let self else { return }
                self.log.info("Tip delivered via updates: \(productID, privacy: .public)")
                if self.phase == .pending { self.phase = .ready }
                self.celebrate()
            }
        }
    }

    /// Called when the Support page goes away, so the next visit starts
    /// clean.
    func dismissThankYou() {
        showsThankYou = false
        purchaseFailed = false
    }

    private func celebrate() {
        showsThankYou = true
        isCelebrating = true
        celebrationTask?.cancel()
        let duration = celebrationDuration
        celebrationTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.isCelebrating = false
        }
    }
}
