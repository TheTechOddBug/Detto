import AppKit
import AVFoundation

@MainActor
final class AudioFeedbackManager {
    static let shared = AudioFeedbackManager()

    private var audioPlayer: AVAudioPlayer?

    private let beginRecordPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/begin_record.caf"
    private let endRecordPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/end_record.caf"

    private init() {}

    func playRecordingStart() {
        playSound(at: beginRecordPath)
    }

    func playRecordingStop() {
        playSound(at: endRecordPath)
    }

    private func playSound(at path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            NSSound(named: "Tink")?.play()
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            NSSound(named: "Tink")?.play()
        }
    }
}
