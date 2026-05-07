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

    @Test("Only talkingWhileMuted carries a composited badge — animations and bare glyphs don't")
    func onlyAlarmHasBadge() {
        // unmuted (bare cat), muted (bare paw-print), talking and
        // pushToTalk (cycling animation) all carry their full signal
        // in the main glyph. talkingWhileMuted is the only state
        // that needs a separate alarm overlay.
        for status in MicStatus.allCases {
            let expected: String? = status == .talkingWhileMuted
                ? "exclamationmark.triangle.fill"
                : nil
            #expect(status.menuBarBadgeSymbol == expected,
                    "badge mismatch for \(status): got \(String(describing: status.menuBarBadgeSymbol))")
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
        // The cycling `talk-1` … `talk-12` frames are the talking
        // signal, so no separate badge symbol is needed.
        #expect(MicStatus.talking.menuBarBadgeSymbol == nil)
    }

    @Test("talkingWhileMuted label signals alert, not plain 'Muted'")
    func talkingWhileMutedIsDistinctFromMuted() {
        #expect(MicStatus.talkingWhileMuted.label != MicStatus.muted.label)
    }

    @Test("muted main glyph is the paw-print asset, no badge")
    func mutedIsBarePawPrint() {
        // A bare paw-print reads as "the cat's resting" — clearer at
        // 18pt than a cat-with-paw-badge composite which crowds itself.
        #expect(MicStatus.muted.menuBarMainSymbol == "paw-print")
        #expect(MicStatus.muted.menuBarBadgeSymbol == nil)
    }

    @Test("talkingWhileMuted badge is an alarm triangle")
    func talkingWhileMutedBadgeIsAlarm() {
        #expect(MicStatus.talkingWhileMuted.menuBarBadgeSymbol == "exclamationmark.triangle.fill")
    }
}
