import Testing
@testable import Mewt

@Suite("MicStatus presentation")
struct MicStatusTests {
    @Test("Main menu-bar glyph is cat for every state except muted (paw-print)")
    func mainSymbolPerState() {
        for status in MicStatus.allCases {
            let expected = status == .muted ? "paw-print" : "cat"
            #expect(status.menuBarMainSymbol == expected,
                    "expected '\(expected)' for \(status), got \(status.menuBarMainSymbol)")
        }
    }

    @Test("No state composites a badge — main glyph or animation carries the full signal")
    func noBadgeForAnyState() {
        for status in MicStatus.allCases {
            #expect(status.menuBarBadgeSymbol == nil,
                    "unexpected badge for \(status): \(String(describing: status.menuBarBadgeSymbol))")
        }
    }

    @Test("Every case has a distinct emoji")
    func distinctEmoji() {
        let emojis = Set(MicStatus.allCases.map(\.emoji))
        #expect(emojis.count == MicStatus.allCases.count)
    }

    @Test("Every case has a non-empty label")
    func nonEmptyLabels() {
        for status in MicStatus.allCases {
            #expect(!status.label.isEmpty, "empty label for \(status)")
        }
    }

    @Test("talking has dedicated label and emoji — animation carries the visual signal")
    func talkingPresentation() {
        #expect(MicStatus.talking.label == "Talking")
        #expect(MicStatus.talking.emoji == "😸")
        #expect(MicStatus.talking.menuBarBadgeSymbol == nil)
    }

    @Test("muted main glyph is the paw-print asset, no badge")
    func mutedIsBarePawPrint() {
        // A bare paw-print reads as "the cat's resting" — clearer at
        // 18pt than a cat-with-paw-badge composite which crowds itself.
        #expect(MicStatus.muted.menuBarMainSymbol == "paw-print")
        #expect(MicStatus.muted.menuBarBadgeSymbol == nil)
    }
}
