import Testing
@testable import Mewt

@Suite("MicStatus presentation")
struct MicStatusTests {
    @Test("Every case has a distinct menu-bar SF Symbol")
    func distinctSymbols() {
        let symbols = Set(MicStatus.allCases.map(\.menuBarSymbol))
        #expect(symbols.count == MicStatus.allCases.count)
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

    @Test("talking has dedicated label, emoji, and symbol")
    func talkingPresentation() {
        #expect(MicStatus.talking.label == "Talking")
        #expect(MicStatus.talking.emoji == "😸")
        #expect(MicStatus.talking.menuBarSymbol == "waveform")
    }

    @Test("talkingWhileMuted label signals alert, not plain 'Muted'")
    func talkingWhileMutedIsDistinctFromMuted() {
        #expect(MicStatus.talkingWhileMuted.label != MicStatus.muted.label)
    }

    @Test("pushToTalk uses a mic-with-plus symbol, not slashed")
    func pushToTalkSymbolIsNotSlashed() {
        #expect(!MicStatus.pushToTalk.menuBarSymbol.contains("slash"))
    }

    @Test("muted uses a slashed mic symbol")
    func mutedSymbolIsSlashed() {
        #expect(MicStatus.muted.menuBarSymbol.contains("slash"))
    }
}
