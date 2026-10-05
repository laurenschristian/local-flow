import Foundation

/// Turns spoken punctuation and layout phrases into their symbols.
enum SpokenCommands {
    private struct Command {
        let regex: NSRegularExpression
        let replacement: String
    }

    // Whisper may glue its own punctuation to a command word ("Comma," or
    // "new line."), so each pattern swallows surrounding whitespace and one
    // trailing punctuation mark.
    private static let commands: [Command] = {
        let phrases: [(String, String)] = [
            ("new paragraph", "\n\n"),
            ("new line", "\n"),
            ("comma", ", "),
            ("full stop", ". "),
            ("period", ". "),
            ("question mark", "? "),
            ("exclamation mark", "! "),
            ("exclamation point", "! "),
            ("semicolon", "; "),
            ("open quote", " \""),
            ("close quote", "\" "),
        ]
        return phrases.compactMap { phrase, symbol in
            let escaped = NSRegularExpression.escapedPattern(for: phrase)
            guard let regex = try? NSRegularExpression(pattern: "(?i)\\s*\\b\(escaped)\\b[.,!?]?\\s*") else { return nil }
            return Command(regex: regex, replacement: symbol)
        }
    }()

    private static let scratchThat = try? NSRegularExpression(pattern: "(?i)\\bscratch that\\b[.,!?]?\\s*")

    static func apply(to text: String) -> String {
        var result = text

        // "scratch that" discards everything said before it.
        if let scratch = scratchThat,
           let last = scratch.matches(in: result, range: fullRange(of: result)).last,
           let range = Range(last.range, in: result) {
            result = String(result[range.upperBound...])
        }

        result = applySelfCorrections(result)

        for command in commands {
            result = command.regex.stringByReplacingMatches(
                in: result,
                range: fullRange(of: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: command.replacement)
            )
        }

        // Tidy artifacts: spaces around newlines, doubled punctuation spacing.
        result = result.replacingOccurrences(of: " \n", with: "\n")
        result = result.replacingOccurrences(of: "\n ", with: "\n")
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // "X, no wait, Y" / "X, I mean Y": a short correction Y at the end of a sentence
    // replaces the same number of words right before the marker.
    private static let correction = try? NSRegularExpression(
        pattern: "(?i)(\\S[^.!?\\n]*?)[,]?\\s+(?:no wait|sorry,? i mean|i mean)[,]?\\s+([^.!?\\n,]+?)([.!?]|$)"
    )

    static func applySelfCorrections(_ text: String) -> String {
        guard let regex = correction else { return text }
        var result = text
        // Rescan after each rewrite so ranges never go stale.
        while let match = regex.firstMatch(in: result, range: fullRange(of: result)),
              let whole = Range(match.range, in: result),
              let beforeRange = Range(match.range(at: 1), in: result),
              let fixRange = Range(match.range(at: 2), in: result),
              let endRange = Range(match.range(at: 3), in: result) {
            let before = result[beforeRange].split(separator: " ")
            let fix = result[fixRange].split(separator: " ")
            guard (1...4).contains(fix.count), before.count > fix.count else { break }
            let kept = (before.dropLast(fix.count) + fix).joined(separator: " ")
            result.replaceSubrange(whole, with: kept + result[endRange])
        }
        return result
    }

    private static func fullRange(of string: String) -> NSRange {
        NSRange(string.startIndex..., in: string)
    }
}
