import AppKit
import StoreKit
import StoreKitTest
import Testing
@testable import Mewt

/// Runs the real backend against the repo-root `Tips.storekit` through a
/// local StoreKit test session — no App Store, no network.
@Suite("StoreKitTipBackend (local StoreKit)", .serialized)
@MainActor
struct StoreKitTipBackendTests {
    private static let configURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tips.storekit")

    /// macOS StoreKit needs a window to anchor the purchase context.
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
        styleMask: [.titled],
        backing: .buffered,
        defer: true
    )

    private func makeSession() throws -> SKTestSession {
        let session = try SKTestSession(contentsOf: Self.configURL)
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    @Test("loads all three tips from Tips.storekit")
    func loadsProducts() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        let products = try await StoreKitTipBackend().loadProducts(ids: TipStore.productIDs)
        #expect(Set(products.map(\.id)) == Set(TipStore.productIDs))
        #expect(Set(products.map(\.displayName)) == ["Treat", "Tuna Can", "Cat Tower"])
    }

    // Not asserted here: that `finish()` clears `Transaction.unfinished`.
    // Under a hosted SKTestSession the finished transaction kept showing
    // as unfinished on most runs (passed once, then failed consistently),
    // so that check moves to the manual Sandbox pass in pre-submission §8.
    @Test("purchase succeeds and is recorded by StoreKit")
    func purchaseSucceeds() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        let backend = StoreKitTipBackend()
        _ = try await backend.loadProducts(ids: TipStore.productIDs)
        let outcome = try await backend.purchase(productID: "com.chaninlaw.Mewt.tip.treat", confirmIn: window)
        #expect(outcome == .success)
        #expect(session.allTransactions().contains { $0.productIdentifier == "com.chaninlaw.Mewt.tip.treat" })
    }

    @Test("Ask to Buy reports pending")
    func askToBuyIsPending() async throws {
        let session = try makeSession()
        defer {
            session.askToBuyEnabled = false
            session.clearTransactions()
        }
        session.askToBuyEnabled = true

        let backend = StoreKitTipBackend()
        _ = try await backend.loadProducts(ids: TipStore.productIDs)
        let outcome = try await backend.purchase(productID: "com.chaninlaw.Mewt.tip.tuna", confirmIn: window)
        #expect(outcome == .pending)
    }

    @Test("unknown product throws")
    func unknownProductThrows() async throws {
        await #expect(throws: TipStoreError.self) {
            try await StoreKitTipBackend().purchase(productID: "nope", confirmIn: nil)
        }
    }
}
