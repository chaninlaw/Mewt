import Testing
@testable import Mewt

@Suite("PoseTagMapping")
struct PoseTagMappingTests {
    @Test("unmuted → .unmuted")
    func unmutedMapping() {
        #expect(PoseTagMapping.tag(for: .unmuted) == .unmuted)
    }

    @Test("muted → .muted")
    func mutedMapping() {
        #expect(PoseTagMapping.tag(for: .muted) == .muted)
    }

    @Test("talking → .talking")
    func talkingMapping() {
        #expect(PoseTagMapping.tag(for: .talking) == .talking)
    }

    @Test("talkingWhileMuted → .talkingWhileMuted")
    func talkingWhileMutedMapping() {
        #expect(PoseTagMapping.tag(for: .talkingWhileMuted) == .talkingWhileMuted)
    }

    @Test("pushToTalk → .pushToTalk")
    func pushToTalkMapping() {
        #expect(PoseTagMapping.tag(for: .pushToTalk) == .pushToTalk)
    }

    @Test("All MicStatus values map to a distinct PoseTag")
    func everyStatusMaps() {
        let tags = Set(MicStatus.allCases.map(PoseTagMapping.tag(for:)))
        #expect(tags.count == MicStatus.allCases.count)
    }
}
