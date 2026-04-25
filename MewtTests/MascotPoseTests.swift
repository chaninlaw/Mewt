import Testing
@testable import Mewt

@Suite("MascotPose mapping")
struct MascotPoseTests {
    // MARK: - Status → pose mappings (one expectation per case)

    @Test("Unmuted → eyes open, smiling, no accent")
    func unmutedPose() {
        let pose = MascotPose.from(.unmuted)
        #expect(pose.eyes == .open)
        #expect(pose.mouth == .smile)
        #expect(pose.accent == .none)
    }

    @Test("Muted → eyes closed, mouth zipped, sleeping accent")
    func mutedPose() {
        let pose = MascotPose.from(.muted)
        #expect(pose.eyes == .closed)
        #expect(pose.mouth == .zipped)
        #expect(pose.accent == .sleeping)
    }

    @Test("Talking-while-muted → wide eyes, shouting, alarm accent")
    func talkingWhileMutedPose() {
        let pose = MascotPose.from(.talkingWhileMuted)
        #expect(pose.eyes == .wide)
        #expect(pose.mouth == .shouting)
        #expect(pose.accent == .alarm)
    }

    @Test("Push-to-talk → excited eyes, open mouth, soundwave accent")
    func pushToTalkPose() {
        let pose = MascotPose.from(.pushToTalk)
        #expect(pose.eyes == .excited)
        #expect(pose.mouth == .open)
        #expect(pose.accent == .soundwave)
    }

    // MARK: - Cross-cutting invariants

    @Test("Every status produces a distinct (eyes, mouth, accent) triple")
    func posesAreDistinct() {
        let all: [MicStatus] = [.unmuted, .muted, .talkingWhileMuted, .pushToTalk]
        let triples = all.map { status -> String in
            let p = MascotPose.from(status)
            return "\(p.eyes)|\(p.mouth)|\(p.accent)"
        }
        #expect(Set(triples).count == all.count, "two statuses share the same pose")
    }

    @Test("Every pose has a non-empty accessibility label")
    func accessibilityLabelsExist() {
        let all: [MicStatus] = [.unmuted, .muted, .talkingWhileMuted, .pushToTalk]
        for status in all {
            #expect(!MascotPose.from(status).accessibilityLabel.isEmpty)
        }
    }

    @Test("talkingWhileMuted accessibility label signals alert (not 'Muted')")
    func alertLabelDistinct() {
        let alert = MascotPose.from(.talkingWhileMuted).accessibilityLabel
        let muted = MascotPose.from(.muted).accessibilityLabel
        #expect(alert != muted)
        #expect(alert.lowercased().contains("talking") || alert.lowercased().contains("mute"))
    }

    @Test("Mapping is deterministic — same input twice yields equal poses")
    func deterministic() {
        #expect(MascotPose.from(.muted) == MascotPose.from(.muted))
        #expect(MascotPose.from(.pushToTalk) == MascotPose.from(.pushToTalk))
    }

    // MARK: - Sleeping accent only when truly muted

    @Test("Sleeping accent is reserved for the resting muted state")
    func sleepingAccentScope() {
        let withSleep: [MicStatus] = [.muted]
        let withoutSleep: [MicStatus] = [.unmuted, .talkingWhileMuted, .pushToTalk]
        for s in withSleep {
            #expect(MascotPose.from(s).accent == .sleeping)
        }
        for s in withoutSleep {
            #expect(MascotPose.from(s).accent != .sleeping, "\(s) must not look asleep")
        }
    }
}
