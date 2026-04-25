import Testing
@testable import Mewt

@Suite("MicStatus presentation")
struct MicStatusTests {
    @Test("Every case has a distinct menu-bar SF Symbol")
    func distinctSymbols() {
        let all: [MicStatus] = [.unmuted, .muted, .talkingWhileMuted, .pushToTalk]
        let symbols = Set(all.map(\.menuBarSymbol))
        #expect(symbols.count == all.count)
    }

    @Test("Every case has a distinct emoji")
    func distinctEmoji() {
        let all: [MicStatus] = [.unmuted, .muted, .talkingWhileMuted, .pushToTalk]
        let emojis = Set(all.map(\.emoji))
        #expect(emojis.count == all.count)
    }

    @Test("Every case has a non-empty label")
    func nonEmptyLabels() {
        let all: [MicStatus] = [.unmuted, .muted, .talkingWhileMuted, .pushToTalk]
        for status in all {
            #expect(!status.label.isEmpty, "empty label for \(status)")
        }
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
