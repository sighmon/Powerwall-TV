import AVFoundation
import Testing
@testable import Powerwall_TV

@MainActor
struct AdvisorSpeechPlaybackTests {
    private final class Player: AdvisorAudioPlaying {
        var delegate: AVAudioPlayerDelegate?
        var starts = true
        var stopped = false
        func play() -> Bool { starts }
        func stop() { stopped = true }
    }
    private enum Failure: Error { case expected }

    @Test func completionAndRepeatedStopReleaseSessionOnce() throws {
        let player = Player()
        var activations = 0
        var releases = 0
        let playback = AdvisorSpeechPlayback(activate: { activations += 1 }, deactivate: { releases += 1 }, makePlayer: { _ in player })
        try playback.play(Data())
        #expect(activations == 1 && releases == 0)
        playback.playbackEnded(player)
        playback.stop()
        #expect(releases == 1 && player.stopped)
        #expect(player.delegate == nil)
    }

    @Test func cancellationAndStartFailureReleaseSession() throws {
        for starts in [true, false] {
            let player = Player()
            player.starts = starts
            var releases = 0
            let playback = AdvisorSpeechPlayback(activate: {}, deactivate: { releases += 1 }, makePlayer: { _ in player })
            if starts {
                try playback.play(Data())
                playback.stop()
            } else {
                do { try playback.play(Data()); Issue.record("Expected playback failure") } catch {}
            }
            #expect(releases == 1 && player.stopped)
        }
    }

    @Test func activationFailureCleansUpAndInvalidAudioDoesNotActivate() {
        var releases = 0
        let playback = AdvisorSpeechPlayback(activate: { throw Failure.expected }, deactivate: { releases += 1 }, makePlayer: { _ in Player() })
        do { try playback.play(Data()); Issue.record("Expected activation failure") } catch {}
        #expect(releases == 1)
        var activations = 0
        let invalid = AdvisorSpeechPlayback(activate: { activations += 1 }, deactivate: {}, makePlayer: { _ in throw Failure.expected })
        do { try invalid.play(Data()); Issue.record("Expected decoding failure") } catch {}
        #expect(activations == 0)
    }

    @Test func staleCompletionCannotStopReplacementPlayback() throws {
        let first = Player()
        let second = Player()
        var created = 0
        var releases = 0
        let playback = AdvisorSpeechPlayback(activate: {}, deactivate: { releases += 1 }, makePlayer: { _ in
            created += 1
            return created == 1 ? first : second
        })
        try playback.play(Data())
        try playback.play(Data())
        playback.playbackEnded(first)
        #expect(releases == 1 && !second.stopped)
        playback.playbackEnded(second)
        #expect(releases == 2 && second.stopped)
    }

    @Test func failedDeactivationRetriesOnClose() throws {
        var attempts = 0
        let playback = AdvisorSpeechPlayback(activate: {}, deactivate: {
            attempts += 1
            if attempts == 1 { throw Failure.expected }
        }, makePlayer: { _ in Player() })
        try playback.play(Data())
        playback.stop()
        playback.stop()
        playback.stop()
        #expect(attempts == 2)
    }
}
