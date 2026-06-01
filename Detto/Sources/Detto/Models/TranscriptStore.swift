import Foundation
import Observation

@Observable
@MainActor
final class TranscriptStore {
    private(set) var utterances: [Utterance] = []
    var volatileYouText: String = ""
    var volatileThemText: String = ""

    /// Timestamp of the most recent finalized utterance
    private(set) var lastUtteranceTimestamp: Date?

    func append(_ utterance: Utterance) {
        utterances.append(utterance)
        lastUtteranceTimestamp = utterance.timestamp
    }

    func updateSpeakerName(at index: Int, name: String) {
        guard utterances.indices.contains(index) else { return }
        utterances[index].speakerName = name
    }

    func updateText(at index: Int, text: String) {
        guard utterances.indices.contains(index) else { return }
        utterances[index].text = text
    }

    func clear() {
        utterances.removeAll()
        volatileYouText = ""
        volatileThemText = ""
        lastUtteranceTimestamp = nil
    }

    func loadDemoData() {
        let base = Date().addingTimeInterval(-600)
        let lines: [(String, Speaker, String, TimeInterval)] = [
            ("Morning everyone. Quick check-in on the migration. Sarah, where are we with the architecture review?", .you, "Speaker 1", 0),
            ("We're in good shape. The team finished the load testing last Thursday and the results look solid. We're seeing about 40% improvement on read latency compared to the current setup.", .them, "Speaker 2", 15),
            ("That tracks with what we expected. The only open question is the data migration strategy. We've got about 800 gigs of historical records and the initial estimate for the cutover window is six hours.", .them, "Speaker 3", 35),
            ("Six hours is tight for a production cutover. Is there a way to do it incrementally?", .you, "Speaker 1", 55),
            ("We've been looking at a dual-write approach. Run both systems in parallel for two weeks, sync incrementally, then flip the switch. The cutover window drops to about 20 minutes.", .them, "Speaker 2", 65),
            ("That sounds much safer. What does it add to the timeline?", .you, "Speaker 1", 80),
            ("About a week. We'd push the staging handoff from June 18th to the 25th, but we can still hit the beta target on July 15th if we compress the QA cycle by a few days.", .them, "Speaker 3", 90),
            ("Let's go with the dual-write approach. I'd rather have a safe cutover than save a week. Can you send me the updated timeline after this call?", .you, "Speaker 1", 110),
        ]
        for (text, speaker, name, offset) in lines {
            utterances.append(Utterance(text: text, speaker: speaker, speakerName: name, timestamp: base.addingTimeInterval(offset)))
        }
        volatileThemText = "Will do. I'll have it over by end of day."
        lastUtteranceTimestamp = utterances.last?.timestamp
    }
}
