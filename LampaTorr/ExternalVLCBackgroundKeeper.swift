import AVFoundation
import Foundation

/// Keeps the host process alive while the official VLC app reads the embedded
/// TorrServer stream over 127.0.0.1. This is intended for personal sideloading:
/// iOS normally suspends a background app, which would stop the local server.
final class ExternalVLCBackgroundKeeper {
    static let shared = ExternalVLCBackgroundKeeper()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    private var isConfigured = false
    private var isRunning = false

    private init() {}

    func start() throws {
        if isRunning { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        if !isConfigured {
            let format = AVAudioFormat(
                standardFormatWithSampleRate: 8_000,
                channels: 1
            )!

            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 0

            guard let silent = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: 8_000
            ) else {
                throw KeeperError.bufferCreationFailed
            }

            silent.frameLength = 8_000
            if let channel = silent.floatChannelData?[0] {
                channel.initialize(repeating: 0, count: Int(silent.frameLength))
            }

            buffer = silent
            isConfigured = true
        }

        guard let buffer else {
            throw KeeperError.bufferCreationFailed
        }

        if !engine.isRunning {
            try engine.start()
        }

        player.scheduleBuffer(buffer, at: nil, options: [.loops])
        player.play()
        isRunning = true

        print("[LampaTorr] External VLC background keeper started")
    }

    func stop() {
        guard isRunning || engine.isRunning else { return }

        player.stop()
        engine.stop()
        engine.reset()
        isRunning = false

        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        } catch {
            print("[LampaTorr] Failed to deactivate background audio session: \(error)")
        }

        print("[LampaTorr] External VLC background keeper stopped")
    }

    enum KeeperError: LocalizedError {
        case bufferCreationFailed

        var errorDescription: String? {
            switch self {
            case .bufferCreationFailed:
                return "Не удалось создать тихий audio keepalive."
            }
        }
    }
}
