import CoreGraphics
import Testing
@testable import Mewt

/// Engine spec §4.6 — integer-snap scale rule.
/// Float-scaled pixel art looks smeared; engine snaps to nearest integer
/// ratio (or 1/n divisor when the frame outsizes the display box).
@Suite("SpriteFrameView integer-snap scale")
struct SpriteFrameScaleTests {
    private static let displaySide: CGFloat = 64

    @Test(
        "Optimal sizes fill the 64pt display box exactly",
        arguments: [
            (frameSide: CGFloat(16),  expectedScale: CGFloat(4),    expectedRendered: CGFloat(64)),
            (frameSide: CGFloat(32),  expectedScale: CGFloat(2),    expectedRendered: CGFloat(64)),
            (frameSide: CGFloat(64),  expectedScale: CGFloat(1),    expectedRendered: CGFloat(64)),
            (frameSide: CGFloat(128), expectedScale: CGFloat(0.5),  expectedRendered: CGFloat(64))
        ]
    )
    func optimalSizesFillBox(frameSide: CGFloat, expectedScale: CGFloat, expectedRendered: CGFloat) {
        let scale = SpriteFrameView.integerSnapScale(frameSide: frameSide, displaySide: Self.displaySide)
        #expect(scale == expectedScale, "scale for \(frameSide)px frame")
        #expect(frameSide * scale == expectedRendered, "rendered size for \(frameSide)px frame")
    }

    @Test(
        "Acceptable sizes integer-snap but render smaller than the box",
        arguments: [
            (frameSide: CGFloat(24), expectedScale: CGFloat(2),   expectedRendered: CGFloat(48)),
            (frameSide: CGFloat(48), expectedScale: CGFloat(1),   expectedRendered: CGFloat(48)),
            (frameSide: CGFloat(92), expectedScale: CGFloat(0.5), expectedRendered: CGFloat(46)),
            (frameSide: CGFloat(96), expectedScale: CGFloat(0.5), expectedRendered: CGFloat(48))
        ]
    )
    func acceptableSizesRenderSmaller(frameSide: CGFloat, expectedScale: CGFloat, expectedRendered: CGFloat) {
        let scale = SpriteFrameView.integerSnapScale(frameSide: frameSide, displaySide: Self.displaySide)
        #expect(scale == expectedScale, "scale for \(frameSide)px frame")
        #expect(frameSide * scale == expectedRendered, "rendered size for \(frameSide)px frame")
        #expect(frameSide * scale < Self.displaySide, "should be smaller than display box")
    }

    @Test("Frame equal to display side renders at 1×")
    func equalRendersAtOne() {
        #expect(SpriteFrameView.integerSnapScale(frameSide: 64, displaySide: 64) == 1)
    }

    @Test(
        "Scale is always either an integer ≥ 1 or 1/integer",
        arguments: stride(from: CGFloat(8), through: CGFloat(256), by: 1).map { $0 }
    )
    func scaleIsAlwaysIntegerOrReciprocal(frameSide: CGFloat) {
        let scale = SpriteFrameView.integerSnapScale(frameSide: frameSide, displaySide: Self.displaySide)
        if frameSide <= Self.displaySide {
            // Upscale path: scale is integer ≥ 1
            #expect(scale >= 1)
            #expect(scale == floor(scale), "upscale must be integer at \(frameSide)px")
        } else {
            // Downscale path: 1/scale is integer ≥ 1
            let inverse = 1.0 / scale
            #expect(inverse >= 1)
            #expect(inverse == floor(inverse), "downscale 1/scale must be integer at \(frameSide)px")
        }
    }

    @Test(
        "Rendered size never exceeds display box",
        arguments: stride(from: CGFloat(8), through: CGFloat(256), by: 4).map { $0 }
    )
    func renderedSizeFitsBox(frameSide: CGFloat) {
        let scale = SpriteFrameView.integerSnapScale(frameSide: frameSide, displaySide: Self.displaySide)
        let rendered = frameSide * scale
        #expect(rendered <= Self.displaySide + 0.001, "rendered \(rendered) > displaySide for \(frameSide)px")
    }

    @Test("Non-positive inputs return 1 (defensive)")
    func nonPositiveReturnsOne() {
        #expect(SpriteFrameView.integerSnapScale(frameSide: 0,    displaySide: 64) == 1)
        #expect(SpriteFrameView.integerSnapScale(frameSide: -8,   displaySide: 64) == 1)
        #expect(SpriteFrameView.integerSnapScale(frameSide: 32,   displaySide: 0)  == 1)
        #expect(SpriteFrameView.integerSnapScale(frameSide: 32,   displaySide: -8) == 1)
    }

    @Test(
        "Display side variations also snap",
        arguments: [
            (frameSide: CGFloat(16), displaySide: CGFloat(32),  expectedScale: CGFloat(2)),
            (frameSide: CGFloat(16), displaySide: CGFloat(96),  expectedScale: CGFloat(6)),
            (frameSide: CGFloat(32), displaySide: CGFloat(96),  expectedScale: CGFloat(3)),
            (frameSide: CGFloat(64), displaySide: CGFloat(128), expectedScale: CGFloat(2))
        ]
    )
    func displaySideVariations(frameSide: CGFloat, displaySide: CGFloat, expectedScale: CGFloat) {
        #expect(SpriteFrameView.integerSnapScale(frameSide: frameSide, displaySide: displaySide) == expectedScale)
    }
}
