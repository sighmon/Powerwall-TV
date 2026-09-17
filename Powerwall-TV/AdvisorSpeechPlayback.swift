import AVFoundation

protocol AdvisorAudioPlaying: AnyObject {
    var delegate: AVAudioPlayerDelegate? { get set }
    func play() -> Bool
    func stop()
}
extension AVAudioPlayer: AdvisorAudioPlaying {}

/// Owns the audio session only while spoken advice is playing.
@MainActor
final class AdvisorSpeechPlayback: NSObject, AVAudioPlayerDelegate {
    private var player: AdvisorAudioPlaying?
    private var sessionActive = false
    private let activate: () throws -> Void
    private let deactivate: () throws -> Void
    private let makePlayer: (Data) throws -> AdvisorAudioPlaying
    private var interruptionObserver: NSObjectProtocol?

    init(
        activate: @escaping () throws -> Void = {
#if os(iOS) || os(tvOS)
            let session = AVAudioSession.sharedInstance()
            // Share the user's media route, including selected AirPlay speakers.
            // Do not override the output port or choose a device ourselves.
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            try session.setActive(true)
#endif
        },
        deactivate: @escaping () throws -> Void = {
#if os(iOS) || os(tvOS)
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
        },
        makePlayer: @escaping (Data) throws -> AdvisorAudioPlaying = { try AVAudioPlayer(data: $0) }
    ) {
        self.activate = activate
        self.deactivate = deactivate
        self.makePlayer = makePlayer
        super.init()
#if os(iOS) || os(tvOS)
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in self?.stop() }
        }
#endif
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    func play(_ data: Data) throws {
        stop()
        do {
            // Decode before activating so malformed audio never interrupts other apps.
            let next = try makePlayer(data)
            player = next
            next.delegate = self
            sessionActive = true
            try activate()
            guard next.play() else { throw PlaybackError.couldNotStart }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        player?.delegate = nil
        player?.stop()
        player = nil
        guard sessionActive else { return }
        do {
            try deactivate()
            sessionActive = false
        } catch {
            // Keep ownership recorded so a later stop/close retries deactivation.
        }
    }

    func playbackEnded(_ finished: AdvisorAudioPlaying) {
        guard let player, player === finished else { return }
        stop()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.playbackEnded(player) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in self?.playbackEnded(player) }
    }

    private enum PlaybackError: LocalizedError {
        case couldNotStart
        var errorDescription: String? { "Could not start spoken advice playback." }
    }
}
