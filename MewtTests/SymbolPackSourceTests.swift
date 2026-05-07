import Testing
import AppKit
import CoreGraphics
import Foundation
@testable import Mewt

@Suite("SymbolPackSource")
struct SymbolPackSourceTests {
    @Test("Emits exactly one pack")
    func oneSymbolPack() {
        let source = SymbolPackSource()
        #expect(source.packs().count == 1)
        #expect(source.packs().first?.id == SymbolPackSource.packId)
    }

    @Test("Pack metadata is stable")
    func packMetadata() {
        let pack = SymbolPackSource().packs().first!
        #expect(pack.tier == .free)
        #expect(pack.author == "Mewt")
        #expect(pack.name == "Mewt (symbols)")
    }

    @Test("Pack has all PoseTags resolved")
    func coversEveryTag() {
        let pack = SymbolPackSource().packs().first!
        for tag in PoseTag.allCases {
            #expect(pack.poses[tag] != nil, "missing pose for \(tag)")
        }
    }

    @Test("tintPolicy is .none so engine doesn't desaturate or overlay")
    func tintPolicyNone() {
        let pack = SymbolPackSource().packs().first!
        #expect(pack.overrides.tintPolicy == .none)
    }

    @Test("Frame ranges are within frames bounds and non-empty")
    func frameRangesValid() {
        let pack = SymbolPackSource().packs().first!
        let frameCount = pack.frames.count
        #expect(frameCount == PoseTag.allCases.count)
        for (tag, anim) in pack.poses {
            #expect(anim.frameRange.lowerBound >= 0,
                    "negative lower bound for \(tag)")
            #expect(anim.frameRange.upperBound <= frameCount,
                    "upper bound out of range for \(tag)")
            #expect(!anim.frameRange.isEmpty,
                    "empty range for \(tag)")
            #expect(anim.loopMode == .freeze,
                    "expected freeze loop for static symbol pose \(tag)")
            #expect(anim.fpsMultiplier == 1.0)
        }
    }

    @Test("Frames are 64-pt squares laid out left-to-right")
    func frameLayout() {
        let pack = SymbolPackSource().packs().first!
        for (i, frame) in pack.frames.enumerated() {
            #expect(frame.rect.width == 64)
            #expect(frame.rect.height == 64)
            #expect(frame.rect.minY == 0)
            #expect(frame.rect.minX == CGFloat(i) * 64)
        }
    }

    @Test @MainActor
    func resourcesReturnedForOwnId() {
        let source = SymbolPackSource()
        let r = source.resources(for: SymbolPackSource.packId)
        #expect(r != nil)
        #expect(r?.packId == SymbolPackSource.packId)
    }

    @Test @MainActor
    func resourcesNilForOtherId() {
        let source = SymbolPackSource()
        #expect(source.resources(for: "com.test.other") == nil)
    }

    @Test @MainActor
    func resourcesSpriteSheetIsNonEmpty() {
        let source = SymbolPackSource()
        let r = source.resources(for: SymbolPackSource.packId)!
        let expectedWidth = CGFloat(PoseTag.allCases.count) * 64
        #expect(r.spriteImage.size.width == expectedWidth)
        #expect(r.spriteImage.size.height == 64)
    }

    /// Catches silent-fail symbol-synthesis failure modes (one cell
    /// rendering as a fully transparent rect on macOS 26). Every cell
    /// must have a noticeable cluster of opaque pixels (>5% of cell
    /// area) for the composite to be visually present.
    @Test @MainActor
    func everyCellHasOpaquePixels() throws {
        let source = SymbolPackSource()
        let img = source.resources(for: SymbolPackSource.packId)!.spriteImage
        let bitmap = try #require(NSBitmapImageRep(data: img.tiffRepresentation!))

        let cellSide = 64
        let area = cellSide * cellSide
        let threshold = area / 20  // 5% of the cell

        for (i, tag) in PoseTag.allCases.enumerated() {
            var opaque = 0
            for y in 0..<cellSide {
                for x in 0..<cellSide {
                    let px = bitmap.colorAt(x: i * cellSide + x, y: y)
                    if (px?.alphaComponent ?? 0) > 0.1 { opaque += 1 }
                }
            }
            #expect(opaque > threshold,
                    "cell for \(tag) renders empty (\(opaque)/\(area) opaque pixels)")
        }
    }
}
