import Foundation

enum Speaker: String, Codable, Sendable {
    case you
    case them
}

struct Utterance: Identifiable, Codable, Sendable {
    let id: UUID
    var text: String
    let speaker: Speaker
    var speakerName: String
    let timestamp: Date
    let confidence: Float?

    init(text: String, speaker: Speaker, speakerName: String? = nil, timestamp: Date = .now, confidence: Float? = nil) {
        self.id = UUID()
        self.text = text
        self.speaker = speaker
        self.speakerName = speakerName ?? (speaker == .you ? "You" : "Them")
        self.timestamp = timestamp
        self.confidence = confidence
    }
}

// MARK: - Session Record

/// Codable record for JSONL session persistence (metadata only, no transcript content)
struct SessionRecord: Codable {
    let speaker: Speaker
    let timestamp: Date
    let speakerName: String?
}
