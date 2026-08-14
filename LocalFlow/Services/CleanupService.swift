import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Optional post-transcription cleanup. Uses Apple's on-device model when
/// available (macOS 26+ with Apple Intelligence), otherwise a conservative
/// rule-based filler strip. Never sends text off the machine.
enum CleanupService {
    static func cleanup(_ text: String) async -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            if let cleaned = await llmCleanup(text) {
                return cleaned
            }
        }
        #endif
        return ruleBasedCleanup(text)
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func llmCleanup(_ text: String) async -> String? {
        let session = LanguageModelSession(instructions: """
        You clean up dictated text. Fix punctuation and capitalization, remove \
        filler words (um, uh, and similar), and fix obvious dictation slips. \
        Keep the wording, tone, and language otherwise unchanged. \
        Reply with only the cleaned text, nothing else.
        """)

        let work = Task { try await session.respond(to: text).content }
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(15))
            work.cancel()
        }
        defer { watchdog.cancel() }

        guard let raw = try? await work.value else {
            print("[Cleanup] On-device model failed or timed out, using rule-based cleanup")
            return nil
        }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // A drastically shorter reply means the model went off script; keep the original.
        guard !cleaned.isEmpty, cleaned.count > text.count / 3 else { return nil }
        return cleaned
    }
    #endif

    static func ruleBasedCleanup(_ text: String) -> String {
        var result = text
        for filler in ["um", "uh", "uhm", "erm", "ehm"] {
            guard let regex = try? NSRegularExpression(pattern: "(?i)\\s*\\b\(filler)\\b[,.]?") else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
