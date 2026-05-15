import Testing
@testable import Mewt

@MainActor
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

    @Test("pushToTalk → .pushToTalk")
    func pushToTalkMapping() {
        #expect(PoseTagMapping.tag(for: .pushToTalk) == .pushToTalk)
    }

    @Test("All MicStatus values map to a distinct PoseTag")
    func everyStatusMaps() {
        // Explicit closure (instead of `.map(PoseTagMapping.tag(for:))`)
        // so isolation infers from the enclosing `@MainActor` function
        // — method-reference form leaks into a nonisolated context and
        // trips the strict-concurrency warning.
        let tags = Set(MicStatus.allCases.map { PoseTagMapping.tag(for: $0) })
        #expect(tags.count == MicStatus.allCases.count)
    }
}
