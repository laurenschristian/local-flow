import Foundation

/// Whisper memorized end-of-video phrases from YouTube subtitles in its
/// training data and emits them as confident transcripts when the audio is
/// silent. We drop these when the audio energy is below a speech threshold.
enum HallucinationFilter {
    static let phrases: Set<String> = [
        "thank you", "thank you.", "thanks for watching", "thanks for watching.",
        "thanks for watching!", "thank you for watching", "thank you for watching.",
        "thank you for watching!", "thanks", "thanks.", "thank you!",
        "you", "you.", ".", "...", "bye", "bye.", "goodbye", "goodbye.",
        "subtitles by the amara.org community",
        "please subscribe", "like and subscribe",
    ]

    // Empirical: real speech RMS is typically > 0.01; ambient noise sits well below.
    static let silenceRMSThreshold: Float = 0.005

    static func isLikelyHallucination(text: String, audio: [Float]) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        guard phrases.contains(normalized) else { return false }

        // Match a known hallucination phrase. Confirm by checking audio energy:
        // if the recording was effectively silent, this is definitely a hallucination.
        guard !audio.isEmpty else { return true }
        var sumSquares: Float = 0
        for sample in audio { sumSquares += sample * sample }
        let rms = sqrt(sumSquares / Float(audio.count))
        return rms < silenceRMSThreshold
    }
}

enum TranscriptionFormatter {
    /// Capitalizes the first letter and guarantees terminal punctuation.
    static func punctuate(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { return result }

        let firstChar = result.removeFirst()
        result = String(firstChar).uppercased() + result

        let lastChar = result.last ?? Character(" ")
        if !".!?".contains(lastChar) {
            result += "."
        }
        return result
    }

    /// Splits sentences into bullet points; single sentences pass through.
    static func bulletSummary(_ text: String) -> String {
        let sentences = text
            .replacingOccurrences(of: "? ", with: "?|")
            .replacingOccurrences(of: ". ", with: ".|")
            .replacingOccurrences(of: "! ", with: "!|")
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if sentences.count <= 1 {
            return text
        }
        return sentences.map { "• \($0)" }.joined(separator: "\n")
    }
}
