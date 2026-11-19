import AppKit
import Testing
@testable import Mewt

@MainActor
final class MockTipBackend: TipStoreBackend {
    struct Failure: Error {}

    var products: [TipProduct] = [
        TipProduct(id: "com.chaninlaw.Mewt.tip.tower", displayName: "Cat Tower", displayPrice: "฿349", price: 349),
        TipProduct(id: "com.chaninlaw.Mewt.tip.treat", displayName: "Treat", displayPrice: "฿35", price: 35),
        TipProduct(id: "com.chaninlaw.Mewt.tip.tuna", displayName: "Tuna Can", displayPrice: "฿99", price: 99),
    ]
    var loadError: (any Error)?
    var outcome: Result<TipPurchaseOutcome, any Error> = .success(.success)
    private(set) var loadCallCount = 0
    private(set) var purchasedIDs: [String] = []
    /// Called mid-purchase so tests can observe the store's in-flight state.
    var onPurchase: (() -> Void)?

    private var updatesContinuation: AsyncStream<String>.Continuation?

    func loadProducts(ids: [String]) async throws -> [TipProduct] {
        loadCallCount += 1
        if let loadError { throw loadError }
        return products
    }

    func purchase(productID: String, confirmIn window: NSWindow?) async throws -> TipPurchaseOutcome {
        purchasedIDs.append(productID)
        onPurchase?()
        return try outcome.get()
    }

    func transactionUpdates() -> AsyncStream<String> {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        updatesContinuation = continuation
        return stream
    }

    func deliverUpdate(_ productID: String) {
        updatesContinuation?.yield(productID)
    }
}

@Suite("TipStore")
@MainActor
struct TipStoreTests {
    private func makeStore() -> (TipStore, MockTipBackend) {
        let backend = MockTipBackend()
        return (TipStore(backend: backend, celebrationDuration: .milliseconds(50)), backend)
    }

    /// Polls on the main actor so tests don't race the listener task under
    /// parallel load.
    private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func loadedStore() async -> (TipStore, MockTipBackend) {
        let (store, backend) = makeStore()
        await store.loadProductsIfNeeded()
        return (store, backend)
    }

    // MARK: - Loading

    @Test("load sorts products by price and becomes ready")
    func loadSortsByPrice() async {
        let (store, _) = await loadedStore()
        #expect(store.phase == .ready)
        #expect(store.products.map(\.displayName) == ["Treat", "Tuna Can", "Cat Tower"])
    }

    @Test("load error shows failed, and the next visit retries")
    func loadErrorRetries() async {
        let (store, backend) = makeStore()
        backend.loadError = MockTipBackend.Failure()
        await store.loadProductsIfNeeded()
        #expect(store.phase == .failed)
        #expect(store.products.isEmpty)

        backend.loadError = nil
        await store.loadProductsIfNeeded()
        #expect(store.phase == .ready)
        #expect(backend.loadCallCount == 2)
    }

    @Test("empty product list counts as failed")
    func emptyIsFailed() async {
        let (store, backend) = makeStore()
        backend.products = []
        await store.loadProductsIfNeeded()
        #expect(store.phase == .failed)
    }

    @Test("already-loaded products are not fetched again")
    func noReloadWhenReady() async {
        let (store, backend) = await loadedStore()
        await store.loadProductsIfNeeded()
        #expect(backend.loadCallCount == 1)
    }

    // MARK: - Purchasing

    @Test("success returns to ready, shows thank-you, then the mascot settles")
    func successCelebrates() async throws {
        let (store, backend) = await loadedStore()
        await store.purchase(store.products[0])
        #expect(backend.purchasedIDs == ["com.chaninlaw.Mewt.tip.treat"])
        #expect(store.phase == .ready)
        #expect(store.showsThankYou)
        #expect(store.isCelebrating)

        await waitUntil { !store.isCelebrating }
        #expect(!store.isCelebrating)
        #expect(store.showsThankYou, "thank-you copy stays until the page is left")
    }

    @Test("cancel is silent")
    func cancelIsSilent() async {
        let (store, backend) = await loadedStore()
        backend.outcome = .success(.userCancelled)
        await store.purchase(store.products[0])
        #expect(store.phase == .ready)
        #expect(!store.showsThankYou)
        #expect(!store.purchaseFailed)
    }

    @Test("pending waits, and an approval via updates celebrates")
    func pendingThenApproved() async throws {
        let (store, backend) = await loadedStore()
        store.startUpdatesListener()
        backend.outcome = .success(.pending)
        await store.purchase(store.products[1])
        #expect(store.phase == .pending)
        #expect(!store.showsThankYou)

        backend.deliverUpdate("com.chaninlaw.Mewt.tip.tuna")
        await waitUntil { store.showsThankYou }
        #expect(store.phase == .ready)
        #expect(store.showsThankYou)
    }

    @Test("a thrown purchase error returns to ready with a quiet failure note")
    func purchaseErrorRecovers() async {
        let (store, backend) = await loadedStore()
        backend.outcome = .failure(MockTipBackend.Failure())
        await store.purchase(store.products[0])
        #expect(store.phase == .ready)
        #expect(store.purchaseFailed)
        #expect(!store.showsThankYou)
    }

    @Test("popover is pinned only while the purchase runs")
    func pinsPopoverDuringPurchase() async {
        let (store, backend) = await loadedStore()
        var pins: [Bool] = []
        store.setPopoverPinned = { pins.append($0) }
        backend.onPurchase = { [weak store] in
            #expect(store?.phase == .purchasing("com.chaninlaw.Mewt.tip.treat"))
            #expect(store?.isPurchasing == true)
        }
        await store.purchase(store.products[0])
        #expect(pins == [true, false])
    }

    @Test("popover is unpinned even when the purchase throws")
    func unpinsOnError() async {
        let (store, backend) = await loadedStore()
        var pins: [Bool] = []
        store.setPopoverPinned = { pins.append($0) }
        backend.outcome = .failure(MockTipBackend.Failure())
        await store.purchase(store.products[0])
        #expect(pins == [true, false])
    }

    @Test("purchase before products load is ignored")
    func purchaseBeforeLoadIgnored() async {
        let (store, backend) = makeStore()
        await store.purchase(backend.products[0])
        #expect(backend.purchasedIDs.isEmpty)
        #expect(store.phase == .idle)
    }

    @Test("leaving the page clears the thank-you and failure notes")
    func dismissClears() async {
        let (store, _) = await loadedStore()
        await store.purchase(store.products[0])
        store.dismissThankYou()
        #expect(!store.showsThankYou)
        #expect(!store.purchaseFailed)
    }
}
