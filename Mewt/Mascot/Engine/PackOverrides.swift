import CoreGraphics
import Foundation

/// Pack-level visual + behavioral overrides resolved at load time. The
/// in-memory shape always has every field populated — `CharacterLoader`
/// merges any partial JSON with `PackOverrides.default` before storing
/// the result into `CharacterPack.overrides`.
///
/// `schemaVersion` increments only on breaking changes; additive keys do
/// not bump it. The loader rejects unknown values via
/// `CharacterLoaderError.unsupportedSchemaVersion`.
struct PackOverrides: Equatable, Sendable, Codable {
    var schemaVersion: Int = 1
    var anchors: Anchors = .default
    var frameRate: AmplitudeFpsCurve = .default
    var perPoseFpsMultiplier: [PoseTag: Double] = [:]
    var tintPolicy: TintPolicy = .auto

    static let `default` = PackOverrides()

    init() {}

    init(
        schemaVersion: Int,
        anchors: Anchors,
        frameRate: AmplitudeFpsCurve,
        perPoseFpsMultiplier: [PoseTag: Double],
        tintPolicy: TintPolicy
    ) {
        self.schemaVersion = schemaVersion
        self.anchors = anchors
        self.frameRate = frameRate
        self.perPoseFpsMultiplier = perPoseFpsMultiplier
        self.tintPolicy = tintPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, anchors, frameRate, perPoseFpsMultiplier, tintPolicy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) {
            self.schemaVersion = v
        }
        if let v = try c.decodeIfPresent(Anchors.self, forKey: .anchors) {
            self.anchors = v
        }
        if let v = try c.decodeIfPresent(AmplitudeFpsCurve.self, forKey: .frameRate) {
            self.frameRate = v
        }
        if let v = try c.decodeIfPresent([PoseTag: Double].self, forKey: .perPoseFpsMultiplier) {
            self.perPoseFpsMultiplier = v
        }
        if let v = try c.decodeIfPresent(TintPolicy.self, forKey: .tintPolicy) {
            self.tintPolicy = v
        }
    }

    /// Resolves the multiplier for a pose, defaulting to `1.0` when not set.
    func fpsMultiplier(for pose: PoseTag) -> Double {
        perPoseFpsMultiplier[pose] ?? 1.0
    }
}

/// Normalized anchor points (x, y in 0…1, top-left origin) inside a
/// single sprite frame. Used by overlays to position the floating Z, the
/// alarm symbol, and the push-to-talk glow without baking them into art.
struct Anchors: Equatable, Sendable, Codable {
    var accentTopRight: NormalizedPoint = NormalizedPoint(x: 0.78, y: 0.18)
    var accentBottomLeft: NormalizedPoint = NormalizedPoint(x: 0.22, y: 0.82)
    var glowCenter: NormalizedPoint = NormalizedPoint(x: 0.50, y: 0.55)

    static let `default` = Anchors()

    init() {}

    init(accentTopRight: NormalizedPoint, accentBottomLeft: NormalizedPoint, glowCenter: NormalizedPoint) {
        self.accentTopRight = accentTopRight
        self.accentBottomLeft = accentBottomLeft
        self.glowCenter = glowCenter
    }

    private enum CodingKeys: String, CodingKey {
        case accentTopRight, accentBottomLeft, glowCenter
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(NormalizedPoint.self, forKey: .accentTopRight) {
            self.accentTopRight = v
        }
        if let v = try c.decodeIfPresent(NormalizedPoint.self, forKey: .accentBottomLeft) {
            self.accentBottomLeft = v
        }
        if let v = try c.decodeIfPresent(NormalizedPoint.self, forKey: .glowCenter) {
            self.glowCenter = v
        }
    }
}

struct NormalizedPoint: Equatable, Sendable, Codable {
    var x: Double
    var y: Double

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// Piecewise-linear amplitude→fps curve. Sampling below the first knee
/// clamps to that knee's fps; above the last knee clamps to the last.
/// Knees are stored sorted by amplitude (loader sorts on ingest).
struct AmplitudeFpsCurve: Equatable, Sendable, Codable {
    var amplitudeToFps: [Knee]

    struct Knee: Equatable, Sendable, Codable {
        var amp: Double
        var fps: Double
    }

    static let `default` = AmplitudeFpsCurve(amplitudeToFps: [
        Knee(amp: 0.00, fps: 0),
        Knee(amp: 0.05, fps: 4),
        Knee(amp: 0.30, fps: 12),
        Knee(amp: 0.60, fps: 18)
    ])

    /// Returns the fps to use at a given amplitude, clamped at both ends.
    func fps(at amplitude: Double) -> Double {
        guard let first = amplitudeToFps.first else { return 0 }
        guard let last = amplitudeToFps.last else { return 0 }
        if amplitude <= first.amp { return first.fps }
        if amplitude >= last.amp  { return last.fps }

        for i in 0..<(amplitudeToFps.count - 1) {
            let lo = amplitudeToFps[i]
            let hi = amplitudeToFps[i + 1]
            if amplitude >= lo.amp && amplitude <= hi.amp {
                let span = hi.amp - lo.amp
                guard span > 0 else { return lo.fps }
                let t = (amplitude - lo.amp) / span
                return lo.fps + t * (hi.fps - lo.fps)
            }
        }
        return last.fps
    }
}
