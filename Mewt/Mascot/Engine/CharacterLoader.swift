import CoreGraphics
import Foundation

enum CharacterLoaderError: Error, Equatable {
    case bundleNotFound(URL)
    case invalidManifest(reason: String)
    case missingIdlePose
    case spriteImageUnreadable
    case unsupportedSchemaVersion(Int)
}

/// What `CharacterLoader` returns: the immutable `Sendable` pack plus
/// the raw PNG bytes. The main actor builds the `NSImage` from
/// `imagePNGData` separately via `PackResources.make(packId:imagePNGData:)`,
/// keeping this type clean for cross-actor use and unit tests.
struct LoadedPack: Equatable, Sendable {
    let pack: CharacterPack
    let imagePNGData: Data
}

/// Pure file → value transform for `.mewtpet` folder bundles.
///
/// No SwiftUI / `NSImage` dependency on purpose — keeps the loader
/// unit-testable with fixture bundles in `MewtTests/Fixtures/`. The
/// caller is expected to build a `PackResources` from the returned
/// PNG bytes on the main actor.
enum CharacterLoader {
    /// File names the loader looks for inside the `.mewtpet` bundle.
    enum Files {
        static let manifest  = "manifest.json"
        static let sprite    = "sprite.json"
        static let spriteImg = "sprite.png"
        static let overrides = "overrides.json"
    }

    private static let supportedManifestSchema = 1
    private static let supportedOverridesSchema = 1

    static func load(bundleURL: URL) throws -> LoadedPack {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: bundleURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw CharacterLoaderError.bundleNotFound(bundleURL)
        }

        let manifestURL  = bundleURL.appendingPathComponent(Files.manifest)
        let spriteURL    = bundleURL.appendingPathComponent(Files.sprite)
        let spriteImgURL = bundleURL.appendingPathComponent(Files.spriteImg)
        let overridesURL = bundleURL.appendingPathComponent(Files.overrides)

        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL)
        } catch {
            throw CharacterLoaderError.invalidManifest(reason: "manifest.json missing or unreadable")
        }
        let manifest = try parseManifest(data: manifestData)

        let spriteData: Data
        do {
            spriteData = try Data(contentsOf: spriteURL)
        } catch {
            throw CharacterLoaderError.invalidManifest(reason: "sprite.json missing or unreadable")
        }
        let sprite = try parseAseprite(data: spriteData)

        let overrides = try parseOverrides(at: overridesURL)

        let imagePNGData: Data
        do {
            imagePNGData = try Data(contentsOf: spriteImgURL)
        } catch {
            throw CharacterLoaderError.spriteImageUnreadable
        }
        guard !imagePNGData.isEmpty else {
            throw CharacterLoaderError.spriteImageUnreadable
        }

        let resolvedPoses = try resolvePoses(
            tagged: sprite.poses,
            overrides: overrides
        )

        let pack = CharacterPack(
            id: manifest.id,
            name: manifest.name,
            author: manifest.author,
            version: manifest.version,
            tier: manifest.tier,
            frames: sprite.frames,
            poses: resolvedPoses,
            overrides: overrides,
            extras: manifest.extras
        )
        return LoadedPack(pack: pack, imagePNGData: imagePNGData)
    }

    /// Locates and loads `Mewt-Default.mewtpet` from the main app bundle.
    static func loadBuiltin() throws -> LoadedPack {
        guard let resourceURL = Bundle.main.resourceURL else {
            throw CharacterLoaderError.bundleNotFound(URL(fileURLWithPath: "/"))
        }
        let bundleURL = resourceURL.appendingPathComponent("Mewt-Default.mewtpet")
        return try load(bundleURL: bundleURL)
    }

    // MARK: - Manifest

    /// Subset of the manifest known at this schema version. Unknown
    /// keys are preserved into `extras` for forward compatibility.
    private struct ParsedManifest {
        let id: String
        let name: String
        let author: String
        let version: String
        let tier: PackTier
        let extras: [String: AnyCodableValue]
    }

    private static func parseManifest(data: Data) throws -> ParsedManifest {
        let decoder = JSONDecoder()
        var dict: [String: AnyCodableValue]
        do {
            dict = try decoder.decode([String: AnyCodableValue].self, from: data)
        } catch {
            throw CharacterLoaderError.invalidManifest(reason: "manifest.json is not a JSON object")
        }

        let schema = try requireInt(&dict, key: "packSchemaVersion")
        guard schema == supportedManifestSchema else {
            throw CharacterLoaderError.unsupportedSchemaVersion(schema)
        }

        let id      = try requireString(&dict, key: "id")
        let name    = try requireString(&dict, key: "name")
        let author  = try requireString(&dict, key: "author")
        let version = try requireString(&dict, key: "version")
        // license is required by spec but unused by engine — consume to keep extras clean
        _ = try requireString(&dict, key: "license")

        let tier: PackTier
        switch dict.removeValue(forKey: "tier") {
        case nil:
            tier = .free
        case .string(let raw)?:
            guard let parsed = PackTier(rawValue: raw) else {
                throw CharacterLoaderError.invalidManifest(reason: "unknown tier '\(raw)'")
            }
            tier = parsed
        case let other?:
            throw CharacterLoaderError.invalidManifest(reason: "tier must be string, got \(other)")
        }

        return ParsedManifest(
            id: id, name: name, author: author, version: version,
            tier: tier, extras: dict
        )
    }

    private static func requireString(_ dict: inout [String: AnyCodableValue], key: String) throws -> String {
        switch dict.removeValue(forKey: key) {
        case .string(let s)?: return s
        case nil: throw CharacterLoaderError.invalidManifest(reason: "missing '\(key)'")
        case let other?: throw CharacterLoaderError.invalidManifest(reason: "'\(key)' must be string, got \(other)")
        }
    }

    private static func requireInt(_ dict: inout [String: AnyCodableValue], key: String) throws -> Int {
        switch dict.removeValue(forKey: key) {
        case .int(let n)?:    return n
        case .double(let d)?: return Int(d)
        case nil: throw CharacterLoaderError.invalidManifest(reason: "missing '\(key)'")
        case let other?: throw CharacterLoaderError.invalidManifest(reason: "'\(key)' must be number, got \(other)")
        }
    }

    // MARK: - Aseprite sprite.json (Array format)

    private struct ParsedSprite {
        let frames: [SpriteFrame]
        /// Pose-keyed animations as found in the file (before fallback resolution).
        /// fpsMultiplier is set to 1.0 here; the loader applies overrides next.
        let poses: [PoseTag: PoseAnimation]
    }

    private struct AsepriteFile: Decodable {
        struct Frame: Decodable {
            struct Rect: Decodable {
                let x: Int
                let y: Int
                let w: Int
                let h: Int
            }
            let frame: Rect
            let duration: Int
        }
        struct Meta: Decodable {
            struct FrameTag: Decodable {
                let name: String
                let from: Int
                let to: Int
                let direction: String
            }
            let frameTags: [FrameTag]
        }
        let frames: [Frame]
        let meta: Meta
    }

    private static func parseAseprite(data: Data) throws -> ParsedSprite {
        let decoder = JSONDecoder()
        let raw: AsepriteFile
        do {
            raw = try decoder.decode(AsepriteFile.self, from: data)
        } catch {
            throw CharacterLoaderError.invalidManifest(reason: "sprite.json is not a recognized Aseprite Array-format export")
        }

        let frames: [SpriteFrame] = raw.frames.map { f in
            SpriteFrame(
                rect: CGRect(x: f.frame.x, y: f.frame.y, width: f.frame.w, height: f.frame.h),
                duration: TimeInterval(f.duration) / 1000.0
            )
        }

        var poses: [PoseTag: PoseAnimation] = [:]
        for tag in raw.meta.frameTags {
            guard let pose = PoseTag(rawValue: tag.name) else { continue }
            guard tag.from >= 0, tag.to >= tag.from, tag.to < frames.count else {
                throw CharacterLoaderError.invalidManifest(
                    reason: "tag '\(tag.name)' frame range \(tag.from)…\(tag.to) is out of bounds for \(frames.count) frames"
                )
            }
            let loopMode = mapDirection(tag.direction)
            poses[pose] = PoseAnimation(
                frameRange: tag.from..<(tag.to + 1),
                loopMode: loopMode,
                fpsMultiplier: 1.0
            )
        }

        return ParsedSprite(frames: frames, poses: poses)
    }

    private static func mapDirection(_ raw: String) -> LoopMode {
        switch raw {
        case "forward":          return .forward
        case "reverse":          return .reverse
        case "pingpong":         return .pingPong
        case "pingpong_reverse": return .pingPongReverse
        default:                 return .forward
        }
    }

    // MARK: - Overrides

    private static func parseOverrides(at url: URL) throws -> PackOverrides {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return .default
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .default
        }
        guard !data.isEmpty else { return .default }

        let decoder = JSONDecoder()
        let parsed: PackOverrides
        do {
            parsed = try decoder.decode(PackOverrides.self, from: data)
        } catch {
            return .default
        }
        guard parsed.schemaVersion == supportedOverridesSchema else {
            throw CharacterLoaderError.unsupportedSchemaVersion(parsed.schemaVersion)
        }
        return parsed
    }

    // MARK: - Pose fallback resolution

    /// Resolves the fallback chain (§4.5) so the renderer never sees a
    /// missing pose. Throws `missingIdlePose` if `idle` is absent.
    /// Bakes in `overrides.perPoseFpsMultiplier` so the renderer can
    /// read `animation.fpsMultiplier` directly without override lookup.
    private static func resolvePoses(
        tagged: [PoseTag: PoseAnimation],
        overrides: PackOverrides
    ) throws -> [PoseTag: PoseAnimation] {
        guard let idleAnim = tagged[.idle] else {
            throw CharacterLoaderError.missingIdlePose
        }

        var resolved = tagged

        if resolved[.unmuted] == nil {
            resolved[.unmuted] = idleAnim
        }

        if resolved[.muted] == nil {
            // Frozen single-frame pose at idle's first frame.
            let lo = idleAnim.frameRange.lowerBound
            resolved[.muted] = PoseAnimation(
                frameRange: lo..<(lo + 1),
                loopMode: .freeze,
                fpsMultiplier: 1.0
            )
        }

        if resolved[.talking] == nil, let fallback = resolved[.unmuted] {
            resolved[.talking] = fallback
        }

        if resolved[.pushToTalk] == nil, let fallback = resolved[.unmuted] {
            resolved[.pushToTalk] = fallback
        }

        // Apply per-pose fps multipliers so renderer doesn't have to.
        for (tag, anim) in resolved {
            let multiplier = overrides.perPoseFpsMultiplier[tag] ?? 1.0
            resolved[tag] = PoseAnimation(
                frameRange: anim.frameRange,
                loopMode: anim.loopMode,
                fpsMultiplier: multiplier
            )
        }

        return resolved
    }
}
