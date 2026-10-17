import XCTest

final class TranscriptionMatcherTests: XCTestCase {
    func testBracketedCuesAreNotWaitedFor() {
        let (tokens, _) = TranscriptionMatcher.tokenize("Hello there [pause, smile] my friends")
        XCTAssertEqual(tokens, ["hello", "there", "my", "friends"])
    }

    func testStrayOpeningBracketHidesNothing() {
        let (tokens, _) = TranscriptionMatcher.tokenize("Prices start at [under fifty dollars")
        XCTAssertEqual(tokens, ["prices", "start", "at", "under", "fifty", "dollars"])
    }

    func testNormalReadingAdvancesWordByWord() {
        let matcher = TranscriptionMatcher()
        matcher.setScript("the quick brown fox jumps over the lazy dog today")
        matcher.ingest("the quick brown")
        XCTAssertEqual(matcher.currentWordIndex, 3)
        // It moves once three new words past the current spot are heard.
        matcher.ingest("the quick brown fox jumps over")
        XCTAssertEqual(matcher.currentWordIndex, 6)
    }

    func testBigJumpWaitsForASecondAgreeingResult() {
        let words = (1...30).map { "word\($0)" }.joined(separator: " ")
        let matcher = TranscriptionMatcher()
        matcher.setScript("alpha beta gamma " + words + " delta epsilon zeta")
        matcher.ingest("delta epsilon zeta")
        XCTAssertEqual(matcher.currentWordIndex, 0, "one far match alone shouldn't move the prompter")
        matcher.ingest("delta epsilon zeta")
        XCTAssertEqual(matcher.currentWordIndex, 0, "nor the same result repeated")
        matcher.ingest("so delta epsilon zeta")
        XCTAssertEqual(matcher.currentWordIndex, 36, "a second result with more words heard should")
    }

    func testHintWordsAreDistinctLongWordsFromTheCurrentPosition() {
        let matcher = TranscriptionMatcher()
        matcher.setScript("Welcome everyone to Kubernetes basics. Kubernetes runs containers [applause] everywhere")
        XCTAssertEqual(matcher.upcomingHintWords(), ["Welcome", "everyone", "Kubernetes", "basics", "containers", "everywhere"])
        matcher.setCurrentIndex(4)
        XCTAssertEqual(matcher.upcomingHintWords(limit: 2), ["basics", "Kubernetes"])
    }

    func testSkippingFurtherThanTheWindowIsFoundOnceTwoResultsAgree() {
        let filler = (1...60).map { "word\($0)" }.joined(separator: " ")
        let matcher = TranscriptionMatcher()
        matcher.setScript("alpha beta gamma " + filler + " delta epsilon zeta eta theta iota kappa")
        matcher.ingest("delta epsilon zeta eta theta iota")
        XCTAssertEqual(matcher.currentWordIndex, 0, "one far match alone shouldn't move the prompter")
        matcher.ingest("so delta epsilon zeta eta theta iota")
        XCTAssertEqual(matcher.currentWordIndex, 69)
    }

    func testFarSkipToleratesARecognitionStutter() {
        let filler = (1...60).map { "word\($0)" }.joined(separator: " ")
        let matcher = TranscriptionMatcher()
        matcher.setScript("alpha beta gamma " + filler + " not often at dinner parties frankly if you work")
        // Heard with a stutter and a wrong word, as recognition often does
        matcher.ingest("not often a dinner dinner parties frankly")
        matcher.ingest("so not often a dinner dinner parties frankly")
        XCTAssertEqual(matcher.currentWordIndex, 69)
    }

    func testAPhraseJustReadDoesntJumpToItsLaterCopy() {
        let gap = (1...60).map { "word\($0)" }.joined(separator: " ")
        let matcher = TranscriptionMatcher()
        matcher.setScript("on this axis here I put fertility rate because " + gap + " so here I put fertility rate here again")
        matcher.setCurrentIndex(9) // just finished reading "...fertility rate because"
        matcher.ingest("on this axis here I put fertility rate because")
        matcher.ingest("on this axis here I put fertility rate because")
        XCTAssertEqual(matcher.currentWordIndex, 9)
    }

    func testFarAwayShortPhrasesDontMoveThePrompter() {
        let filler = (1...60).map { "word\($0)" }.joined(separator: " ")
        let matcher = TranscriptionMatcher()
        matcher.setScript("alpha beta gamma " + filler + " delta epsilon zeta eta theta iota")
        // Three matching words are enough nearby, but not for a jump past the window
        matcher.ingest("delta epsilon zeta")
        matcher.ingest("delta epsilon zeta")
        XCTAssertEqual(matcher.currentWordIndex, 0)
        // Off-script talk that matches nothing holds still too
        matcher.ingest("I had a sandwich for lunch today")
        matcher.ingest("I had a sandwich for lunch today")
        XCTAssertEqual(matcher.currentWordIndex, 0)
    }

    func testAWrongJumpIsUndoneWhenReadingContinuesWhereItWas() {
        let gap = (1...60).map { "word\($0)" }.joined(separator: " ")
        let matcher = TranscriptionMatcher()
        // The speaker says a line that isn't in the script here but appears later
        matcher.setScript("both apps pages two feature a white font in the corners " + gap
            + " we use a colorful line graph to indicate the heart rate during sleep")
        matcher.setCurrentIndex(3)
        matcher.ingest("one include a colorful line graph indicating the heart rate")
        matcher.ingest("one include a colorful line graph indicating the heart rate during")
        XCTAssertGreaterThan(matcher.currentWordIndex, 60, "it jumps to the later copy")
        // ...but the speaker carries on from where they were
        matcher.ingest("two feature a white font")
        matcher.ingest("two feature a white font in the")
        XCTAssertLessThan(matcher.currentWordIndex, 15)
    }
}
