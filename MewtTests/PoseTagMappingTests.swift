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

    @Test("talkingWhileMuted → .talkingWhileMuted")
    func talkingWhileMutedMapping() {
        #expect(PoseTagMapping.tag(for: .talkingWhileMuted) == .talkingWhileMuted)
    }

    @Test("pushToTalk → .pushToTalk")
    func pushToTalkMapping() {
        #expect(PoseTagMapping.tag(for: .pushToTalk) == .pushToTalk)
    }

    @Test("All MicStatus values map to a defined PoseTag")
    func everyStatusMaps() {
        let cases: [MicStatus] = [.unmuted, .muted, .talkingWhileMuted, .pushToTalk]
        let tags = Set(cases.map(PoseTagMapping.tag(for:)))
        #expect(tags.count == cases.count)
    }
}
