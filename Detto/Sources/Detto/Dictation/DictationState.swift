import Foundation

enum DictationRecordingState {
    case idle
    case loadingModel
    case recording
    case transcribing
}

@Observable @MainActor
final class DictationState {
    var recordingState: DictationRecordingState = .idle
    var audioLevel: Float = 0
    var recordingDuration: TimeInterval = 0
    var lastDictationJustFinished = false
    var isModelLoaded = false
    var modelDownloadProgress: Double = 0
    var hasAccessibilityPermission = false
    var hasMicrophonePermission = false
    var lastError: String?
}
