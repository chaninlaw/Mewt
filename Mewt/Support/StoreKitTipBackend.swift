import AppKit
import StoreKit

enum TipStoreError: Error {
    case unknownProduct(String)
    /// StoreKit couldn't verify the transaction's signature.
    case unverified
}

/// Real `TipStoreBackend`. Talks to `storekitagent`, so the app needs no
/// network entitlement.
@MainActor
final class StoreKitTipBackend: TipStoreBackend {
    private var productsByID: [String: Product] = [:]

    func loadProducts(ids: [String]) async throws -> [TipProduct] {
        let loaded = try await Product.products(for: ids)
        productsByID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        return loaded.map {
            TipProduct(id: $0.id, displayName: $0.displayName, displayPrice: $0.displayPrice, price: $0.price)
        }
    }

    func purchase(productID: String, confirmIn window: NSWindow?) async throws -> TipPurchaseOutcome {
        guard let product = productsByID[productID] else { throw TipStoreError.unknownProduct(productID) }
        // On macOS the window-less `purchase()` throws
        // `.invalidPresentationContext`, so always anchor to a window.
        let result: Product.PurchaseResult
        if let anchor = window ?? NSApp.keyWindow {
            result = try await product.purchase(confirmIn: anchor)
        } else {
            result = try await product.purchase()
        }
        switch result {
        case .success(let verification):
            // Unverified transactions stay unfinished; StoreKit redelivers
            // them and `transactionUpdates()` skips them again.
            guard case .verified(let transaction) = verification else { throw TipStoreError.unverified }
            await transaction.finish()
            return .success
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .userCancelled
        }
    }

    func transactionUpdates() -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    guard case .verified(let transaction) = result else { continue }
                    await transaction.finish()
                    continuation.yield(transaction.productID)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
