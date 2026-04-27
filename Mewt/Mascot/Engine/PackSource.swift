import Foundation

/// Source of `CharacterPack`s. Foundation ships only `BundledPackSource`
/// + `SafePackSource`; Plus and Studio plug in additional sources without
/// touching `CharacterCatalog` or `AppState`.
///
/// `packs()` returns metadata only and may be called from any actor.
/// `resources(for:)` builds the GUI-bound `PackResources` and runs on the
/// main actor where `NSImage` decoding is safe.
protocol PackSource: Sendable {
    func packs() -> [CharacterPack]
    @MainActor func resources(for packId: String) -> PackResources?
}
