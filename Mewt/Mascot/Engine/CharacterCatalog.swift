import Foundation
import Observation

/// Owns the set of available `CharacterPack`s and the user's selection.
/// Foundation phase wires a single `BundledPackSource` (or
/// `SafePackSource` if bundled load fails); Plus / Studio extend the
/// source list without changing this type or `AppState`'s contract.
///
/// Resolution order for `currentPack()`:
///
///   1. A pack with `id == selectedPackId` from any source
///   2. A pack with `id == defaultPackId`
///   3. The first pack from any source (procedural safe fallback if
///      the only source is `SafePackSource`)
@MainActor
@Observable
final class CharacterCatalog {
    let sources: [any PackSource]
    let defaultPackId: String

    /// Selected pack id. Mutating writes back to `selectionStorage` if
    /// one was provided so user choice persists across launches.
    var selectedPackId: String {
        didSet {
            guard oldValue != selectedPackId else { return }
            selectionStorage?.set(selectedPackId, forKey: Self.selectionDefaultsKey)
            invalidateResourcesCache()
        }
    }

    @ObservationIgnored
    private let selectionStorage: UserDefaults?
    @ObservationIgnored
    private var resourcesCache: PackResources?
    @ObservationIgnored
    private var resourcesCacheId: String?

    static let selectionDefaultsKey = "mascot.selectedPackId"

    init(
        sources: [any PackSource],
        defaultPackId: String,
        selectionStorage: UserDefaults? = nil
    ) {
        self.sources = sources
        self.defaultPackId = defaultPackId
        self.selectionStorage = selectionStorage
        // Restore persisted selection if any; otherwise start at default.
        let stored = selectionStorage?.string(forKey: Self.selectionDefaultsKey)
        self.selectedPackId = stored ?? defaultPackId
    }

    func allPacks() -> [CharacterPack] {
        sources.flatMap { $0.packs() }
    }

    /// Resolves the active pack per the rules above. Always returns
    /// something — caller never needs to handle `nil`.
    func currentPack() -> CharacterPack {
        let all = allPacks()
        if let selected = all.first(where: { $0.id == selectedPackId }) {
            return selected
        }
        if let fallback = all.first(where: { $0.id == defaultPackId }) {
            return fallback
        }
        if let any = all.first {
            return any
        }
        // No source produced any pack — this shouldn't happen because
        // AppState always wires at least SafePackSource. Construct one
        // on the spot to keep the contract of "always returns".
        return SafePackSource().packs().first!
    }

    /// Decoded sprite image for the current pack. Cached until the
    /// selection changes so SwiftUI redraws don't re-decode the PNG.
    func currentResources() -> PackResources {
        let pack = currentPack()
        if let cached = resourcesCache, resourcesCacheId == pack.id {
            return cached
        }
        for source in sources {
            if let r = source.resources(for: pack.id) {
                resourcesCache = r
                resourcesCacheId = pack.id
                return r
            }
        }
        // Last-ditch synthesis if no source has resources for the
        // pack's id — surface the safe procedural circle rather than
        // crash. SafePackSource.resources never returns nil for its
        // own packId, so the force-unwrap is total.
        let safe = SafePackSource()
        let r = safe.resources(for: SafePackSource.packId)!
        resourcesCache = r
        resourcesCacheId = r.packId
        return r
    }

    private func invalidateResourcesCache() {
        resourcesCache = nil
        resourcesCacheId = nil
    }
}
