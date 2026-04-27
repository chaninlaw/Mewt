import Foundation
import os

/// Source that auto-discovers `.mewtpet` folder bundles in
/// `Bundle.main.resourceURL`. In foundation phase only
/// `Mewt-Default.mewtpet` ships; Plus drops in more pack folders without
/// touching this type.
///
/// Throws on init when no packs were discovered or all discovered packs
/// fail to load — the caller (`AppState`) is expected to fall back to
/// `SafePackSource` so the app still launches with a visible mascot.
struct BundledPackSource: PackSource {
    private static let log = Logger(subsystem: "com.chaninlaw.Mewt", category: "MascotEngine")

    private let loaded: [String: LoadedPack]

    init(resourceURL: URL? = Bundle.main.resourceURL) throws {
        guard let resourceURL else {
            throw CharacterLoaderError.bundleNotFound(URL(fileURLWithPath: "/"))
        }

        let fm = FileManager.default
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: resourceURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
        } catch {
            throw CharacterLoaderError.bundleNotFound(resourceURL)
        }

        var collected: [String: LoadedPack] = [:]
        for url in entries where url.pathExtension == "mewtpet" {
            do {
                let pack = try CharacterLoader.load(bundleURL: url)
                collected[pack.pack.id] = pack
            } catch {
                Self.log.error(
                    "Failed to load .mewtpet at \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }

        guard !collected.isEmpty else {
            throw CharacterLoaderError.bundleNotFound(resourceURL)
        }

        self.loaded = collected
    }

    func packs() -> [CharacterPack] {
        loaded.values.map(\.pack)
    }

    @MainActor
    func resources(for packId: String) -> PackResources? {
        guard let entry = loaded[packId] else { return nil }
        return PackResources.make(packId: packId, imagePNGData: entry.imagePNGData)
    }
}
