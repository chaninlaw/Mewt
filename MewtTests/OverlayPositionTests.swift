import CoreGraphics
import Testing
@testable import Mewt

@Suite("OverlayPosition geometry")
struct OverlayPositionTests {
    // A typical primary-display visibleFrame: origin (0, 0), 1440 × 875
    // (1080 minus dock+menu bar). Mascot is 64 × 64.
    private let frame = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let size = CGSize(width: 64, height: 64)

    // MARK: - clamp

    @Test("Origin already inside frame is unchanged")
    func clampIdentity() {
        let p = CGPoint(x: 200, y: 200)
        #expect(OverlayPosition.clamp(p, size: size, within: frame) == p)
    }

    @Test("Origin past right edge clamps to maxX - width")
    func clampRight() {
        let p = CGPoint(x: 9999, y: 100)
        let clamped = OverlayPosition.clamp(p, size: size, within: frame)
        #expect(clamped.x == frame.maxX - size.width)
        #expect(clamped.y == 100)
    }

    @Test("Origin past top edge clamps to maxY - height")
    func clampTop() {
        let p = CGPoint(x: 100, y: 9999)
        let clamped = OverlayPosition.clamp(p, size: size, within: frame)
        #expect(clamped.y == frame.maxY - size.height)
        #expect(clamped.x == 100)
    }

    @Test("Origin past left edge clamps to minX")
    func clampLeft() {
        let p = CGPoint(x: -500, y: 100)
        let clamped = OverlayPosition.clamp(p, size: size, within: frame)
        #expect(clamped.x == frame.minX)
        #expect(clamped.y == 100)
    }

    @Test("Origin past bottom edge clamps to minY")
    func clampBottom() {
        let p = CGPoint(x: 100, y: -500)
        let clamped = OverlayPosition.clamp(p, size: size, within: frame)
        #expect(clamped.y == frame.minY)
        #expect(clamped.x == 100)
    }

    @Test("Frame offset to non-zero origin still clamps correctly")
    func clampOffsetFrame() {
        // Secondary display starting at (1440, -300), 1920 × 1080.
        // visibleFrame.minY = -300, visibleFrame.maxY = 780 — so we need
        // an origin that is off the frame in *both* axes to exercise both
        // lower bounds; (0, -1000) is below-left of the secondary screen.
        let secondary = CGRect(x: 1440, y: -300, width: 1920, height: 1080)
        let p = CGPoint(x: 0, y: -1000)
        let clamped = OverlayPosition.clamp(p, size: size, within: secondary)
        #expect(clamped.x == secondary.minX)
        #expect(clamped.y == secondary.minY)
    }

    @Test("Window larger than frame degrades gracefully (no NaN)")
    func clampOversize() {
        let big = CGSize(width: 5000, height: 5000)
        let clamped = OverlayPosition.clamp(.zero, size: big, within: frame)
        #expect(clamped.x.isFinite)
        #expect(clamped.y.isFinite)
        #expect(clamped == CGPoint(x: frame.minX, y: frame.minY))
    }

    // MARK: - defaultOrigin

    @Test("Default origin sits 32pt inset from bottom-right edges")
    func defaultBottomRight() {
        let origin = OverlayPosition.defaultOrigin(size: size, within: frame)
        #expect(origin.x == frame.maxX - size.width - 32)
        #expect(origin.y == frame.minY + 32)
    }

    @Test("Default origin respects offset frame (secondary display)")
    func defaultOnOffsetFrame() {
        let secondary = CGRect(x: 1440, y: -300, width: 1920, height: 1080)
        let origin = OverlayPosition.defaultOrigin(size: size, within: secondary)
        #expect(origin.x == secondary.maxX - size.width - 32)
        #expect(origin.y == secondary.minY + 32)
    }
}
