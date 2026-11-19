import SwiftUI

/// "Support Mewt" sub-page, opened from the heart in the main popover
/// footer. Layout B from prototype #5.
struct SupportPage: View {
    @Environment(TipStore.self) private var store
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

            Text("Mewt is free and stays free. If you enjoy having Mewt on your menu bar, you can support its development with a tip.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            tips

            Text("Tips are one-time and unlock nothing.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if store.phase == .pending {
                Label("Waiting for approval…", systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if store.purchaseFailed {
                Text("The purchase didn't go through. Please try again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if store.showsThankYou {
                ThankYouBanner(reacting: store.isCelebrating)
            }
        }
        .task { await store.loadProductsIfNeeded() }
        .onDisappear { store.dismissThankYou() }
        .animation(.smooth, value: store.showsThankYou)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal:   .move(edge: .trailing).combined(with: .opacity)
        ))
    }

    @ViewBuilder private var tips: some View {
        switch store.phase {
        case .idle, .loading:
            HStack(spacing: 8) {
                ForEach(Self.placeholders) { TipCard(product: $0, busy: false, action: {}) }
            }
            .redacted(reason: .placeholder)
            .disabled(true)
        case .failed:
            Text("Tips are unavailable right now.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .ready, .purchasing, .pending:
            HStack(spacing: 8) {
                ForEach(store.products) { product in
                    TipCard(product: product, busy: store.phase == .purchasing(product.id)) {
                        Task { await store.purchase(product) }
                    }
                    .disabled(store.isPurchasing)
                }
            }
        }
    }

    private static let placeholders: [TipProduct] = zip(TipStore.productIDs, ["Treat", "Tuna Can", "Cat Tower"]).map {
        TipProduct(id: $0, displayName: $1, displayPrice: "฿00", price: 0)
    }
}

private struct TipCard: View {
    let product: TipProduct
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(Self.emoji(for: product.id)).font(.largeTitle)
                Text(product.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Group {
                    if busy { ProgressView().controlSize(.mini) } else { Text(product.displayPrice) }
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
        .accessibilityLabel("\(product.displayName) tip, \(product.displayPrice)")
    }

    private static func emoji(for id: String) -> String {
        if id.hasSuffix(".treat") { return "🐟" }
        if id.hasSuffix(".tuna") { return "🥫" }
        return "🏰"
    }
}

private struct ThankYouBanner: View {
    let reacting: Bool

    var body: some View {
        HStack(spacing: 8) {
            if reacting {
                VectorPoseView(status: .talking, size: 32)
                    .transition(.scale.combined(with: .opacity))
            }
            Text("Thank you for supporting Mewt! ❤️")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.smooth, value: reacting)
    }
}
