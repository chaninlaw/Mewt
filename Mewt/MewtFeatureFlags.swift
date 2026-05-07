import Foundation

/// Compile-time feature flags. Flip a constant + rebuild — no UI, no
/// UserDefaults override, no runtime branch a user can hit by accident.
///
/// Keep entries sparse. A flag that lives here longer than it takes to
/// ship the gated work should be deleted (along with the dead branch)
/// rather than become a permanent fork.
enum MewtFeatureFlags {
    /// Enables `BundledPackSource` discovery of `.mewtpet` folders in
    /// the app bundle. Off until real pixel art lands — the Default cat
    /// pack folder still ships in `Resources/` (it's part of the
    /// in-progress art work) but is dormant: the catalog never sees it.
    /// While off, `SymbolPackSource` is the user-facing default.
    static let bundledPackEnabled = false
}
