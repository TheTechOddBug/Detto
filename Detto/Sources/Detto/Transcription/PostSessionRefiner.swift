import Foundation
import GrembleVoiceCore
import GrembleVoiceRefinement

struct PostSessionRefiner {
    struct Correction: Sendable {
        let index: Int
        let original: String
        let refined: String
    }

    private static let systemPrompt = """
        You are correcting automated speech recognition errors in a meeting transcript. \
        Fix misspelled proper nouns, punctuation, and minor grammar issues.
        Rules:
        - Make minimal changes. Preserve the speaker's exact words and sentence structure.
        - Fix proper noun spelling (people, places, organizations, acronyms).
        - Do not add, remove, or rearrange sentences.
        - Do not remove filler words (um, uh, like, you know).
        - Output only the corrected text, nothing else.
        """

    /// Refine utterances with the on-device LLM.
    ///
    /// Pass the app's resident refiner (the dictation pipeline's) via
    /// `reusing:` so the already-loaded model is used instead of loading a
    /// second ~1.8 GB copy. A borrowed refiner is never unloaded here. Only
    /// when no refiner is supplied does this fall back to a temporary
    /// load/unload cycle.
    static func refine(
        _ utterances: [Utterance],
        reusing residentRefiner: PrefillMLXRefiner? = nil
    ) async -> [Correction] {
        guard !utterances.isEmpty else { return [] }

        engineLog("[REFINE] Starting post-session refinement for \(utterances.count) utterances")

        let refiner: PrefillMLXRefiner
        let ownsRefiner: Bool
        if let residentRefiner, await residentRefiner.isModelLoaded {
            engineLog("[REFINE] Reusing resident MLX refiner")
            refiner = residentRefiner
            ownsRefiner = false
        } else {
            refiner = PrefillMLXRefiner()
            ownsRefiner = true
            do {
                try await refiner.loadModel()
            } catch {
                engineLog("[REFINE] Model not available, skipping refinement: \(error.localizedDescription)")
                return []
            }
        }

        try? await refiner.prefill(systemPrompt: systemPrompt)

        var corrections: [Correction] = []

        for i in utterances.indices {
            let utterance = utterances[i]
            let wordCount = utterance.text.split(separator: " ").count
            guard wordCount >= 4 else { continue }

            if let conf = utterance.confidence, conf > 0.95 { continue }

            let contextStart = max(0, i - 3)
            let contextLines = utterances[contextStart..<i]
                .map { "\($0.speakerName): \($0.text)" }
                .joined(separator: "\n")

            let input: String
            if contextLines.isEmpty {
                input = utterance.text
            } else {
                input = "[Context - do not modify]\n\(contextLines)\n\n[Correct this utterance only - output the corrected text and nothing else]\n\(utterance.text)"
            }

            do {
                let result = try await refiner.refine(
                    text: input, context: nil, customPrompt: systemPrompt
                )

                let validation = RefinementValidator.validate(
                    result: result, original: utterance.text, isStructuredContext: false
                )

                switch validation {
                case .accept:
                    if result != utterance.text {
                        corrections.append(Correction(
                            index: i, original: utterance.text, refined: result
                        ))
                        engineLog("[REFINE] \(i): \"\(utterance.text.prefix(50))\" -> \"\(result.prefix(50))\"")
                    }
                case .fallback(let reason):
                    engineLog("[REFINE] \(i): rejected (\(reason))")
                }
            } catch {
                engineLog("[REFINE] \(i): error: \(error.localizedDescription)")
            }
        }

        if ownsRefiner {
            await refiner.unloadModel()
        }
        // Return the batch's Metal buffers to the OS either way — post-session
        // refinement is bursty work whose working set shouldn't stay resident.
        MLXMemory.clearCache()
        engineLog("[REFINE] Complete: \(corrections.count)/\(utterances.count) utterances refined")
        return corrections
    }
}
