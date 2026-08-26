import XCTest

final class HallucinationFilterTests: XCTestCase {
    private func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(16000 * seconds))
    }

    private func loudAudio(seconds: Double) -> [Float] {
        (0..<Int(16000 * seconds)).map { Float(sin(Double($0) * 0.1)) * 0.3 }
    }

    func testKnownPhraseOverSilenceIsDropped() {
        XCTAssertTrue(HallucinationFilter.isLikelyHallucination(text: "Thank you.", audio: silence(seconds: 2)))
        XCTAssertTrue(HallucinationFilter.isLikelyHallucination(text: "thanks for watching!", audio: silence(seconds: 2)))
    }

    func testKnownPhraseOverRealSpeechIsKept() {
        XCTAssertFalse(HallucinationFilter.isLikelyHallucination(text: "Thank you.", audio: loudAudio(seconds: 2)))
    }

    func testNormalTextIsNeverDropped() {
        XCTAssertFalse(HallucinationFilter.isLikelyHallucination(text: "Send the report by Friday", audio: silence(seconds: 2)))
    }

    func testEmptyTextIsNotAHallucination() {
        XCTAssertFalse(HallucinationFilter.isLikelyHallucination(text: "   ", audio: silence(seconds: 1)))
    }

    func testPhraseWithEmptyAudioIsDropped() {
        XCTAssertTrue(HallucinationFilter.isLikelyHallucination(text: "you", audio: []))
    }
}

final class TranscriptionFormatterTests: XCTestCase {
    func testPunctuateCapitalizesAndAddsPeriod() {
        XCTAssertEqual(TranscriptionFormatter.punctuate("hello world"), "Hello world.")
    }

    func testPunctuateKeepsExistingTerminalPunctuation() {
        XCTAssertEqual(TranscriptionFormatter.punctuate("really?"), "Really?")
        XCTAssertEqual(TranscriptionFormatter.punctuate("stop!"), "Stop!")
    }

    func testPunctuateTrimsWhitespace() {
        XCTAssertEqual(TranscriptionFormatter.punctuate("  hi  "), "Hi.")
    }

    func testPunctuateEmptyStringStaysEmpty() {
        XCTAssertEqual(TranscriptionFormatter.punctuate("   "), "")
    }

    func testBulletSummarySplitsSentences() {
        let input = "First point. Second point. Third point."
        let expected = "• First point.\n• Second point.\n• Third point."
        XCTAssertEqual(TranscriptionFormatter.bulletSummary(input), expected)
    }

    func testBulletSummarySingleSentencePassesThrough() {
        XCTAssertEqual(TranscriptionFormatter.bulletSummary("Just one thought"), "Just one thought")
    }
}

final class SpokenCommandsTests: XCTestCase {
    func testCommaCommand() {
        XCTAssertEqual(SpokenCommands.apply(to: "apples comma oranges"), "apples, oranges")
    }

    func testNewLineCommand() {
        XCTAssertEqual(SpokenCommands.apply(to: "first line new line second line"), "first line\nsecond line")
    }

    func testPlainTextUntouched() {
        XCTAssertEqual(SpokenCommands.apply(to: "no commands here"), "no commands here")
    }
}

final class SilenceTrimmerTests: XCTestCase {
    private let sampleRate = 16000

    private func speech(seconds: Double) -> [Float] {
        (0..<Int(Double(sampleRate) * seconds)).map { Float(sin(Double($0) * 0.2)) * 0.2 }
    }

    private func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(Double(sampleRate) * seconds))
    }

    func testShortInputPassesThroughUnchanged() {
        let input = silence(seconds: 0.2)
        XCTAssertEqual(SilenceTrimmer.trim(input), input)
    }

    func testAllSilenceIsReturnedUnchanged() {
        let input = silence(seconds: 3)
        XCTAssertEqual(SilenceTrimmer.trim(input), input)
    }

    func testLeadingAndTrailingSilenceIsCut() {
        let input = silence(seconds: 3) + speech(seconds: 2) + silence(seconds: 3)
        let trimmed = SilenceTrimmer.trim(input)
        XCTAssertLessThan(trimmed.count, input.count)
        // Speech plus its 300ms context pad on both sides must survive.
        XCTAssertGreaterThanOrEqual(trimmed.count, Int(2.0 * Double(sampleRate)))
        XCTAssertLessThanOrEqual(trimmed.count, Int(3.0 * Double(sampleRate)))
    }

    func testLongInternalPauseIsCollapsed() {
        let input = speech(seconds: 1) + silence(seconds: 4) + speech(seconds: 1)
        let trimmed = SilenceTrimmer.trim(input)
        // The 4s gap collapses to roughly 0.5s.
        XCTAssertLessThan(trimmed.count, Int(3.5 * Double(sampleRate)))
        XCTAssertGreaterThanOrEqual(trimmed.count, Int(2.0 * Double(sampleRate)))
    }

    func testTrimmedAudioIsNeverEmptyWhenSpeechExists() {
        let input = silence(seconds: 2) + speech(seconds: 0.5) + silence(seconds: 2)
        XCTAssertFalse(SilenceTrimmer.trim(input).isEmpty)
    }
}
