import Foundation

/// Maps recognized speech back to a position in the script.
/// Designed to tolerate improvisation, skipped lines, and mispronunciations
/// by using a rolling fuzzy lookahead match. Words inside [brackets] are stage
/// directions: they stay on screen but are never waited for.
final class TranscriptionMatcher: ObservableObject {
    /// Index into `tokens` of the word the user most recently spoke.
    @Published private(set) var currentWordIndex: Int = 0
    /// Character offset in the original script of `currentWordIndex`.
    @Published private(set) var currentCharOffset: Int = 0
    /// Total words in the script.
    @Published private(set) var totalTokens: Int = 0

    /// Normalized script tokens (lowercased, stripped).
    private var tokens: [String] = []
    /// The same words as written in the script, for recognition hints.
    private var rawTokens: [String] = []
    /// Parallel array: NSRange of each token in the original script string.
    private var tokenRanges: [NSRange] = []
    /// Raw script (for offset calculation).
    private var script: String = ""

    /// How far ahead in the script we scan for matches.
    private let lookAhead = 40
    /// Minimum per-word similarity (0..1) to accept a match.
    private let minWordSimilarity: Float = 0.65
    /// Minimum phrase similarity (average over matched window).
    private let minPhraseSimilarity: Float = 0.55
    /// How many recognized words to match as a group.
    private let phraseSize = 3
    /// When nothing matches within `lookAhead`, the rest of the script is searched
    /// for the last `widePhraseSize` heard words: at least `wideMinMatched` words of
    /// four letters or more, in order, within a short stretch. Short words ("the",
    /// "and") don't count, so they can't make chance matches, and skipping the odd
    /// word copes with recognition stutters ("a dinner dinner parties").
    private let widePhraseSize = 8
    private let wideMinMatched = 4
    private let wideMinWordSimilarity: Float = 0.75
    /// How far back to look for the heard words before jumping ahead: if they fit
    /// text just read, the speaker hasn't moved on, even when they also fit later.
    private let lookBehind = 30

    /// Tracks how many recognized words we've already consumed, so we don't
    /// rematch the same recognized prefix on every partial result.
    private var lastRecognizedWordCount = 0

    /// A move of up to this many words is taken at once (normal reading).
    private let smallStep = 3
    /// Recent match positions. A bigger jump (skipping ahead, or a stray match
    /// when words arrive late) is taken only once two recent results agree:
    /// the same spot, or a few words further on.
    private var recentCandidates: [(index: Int, heardWords: Int)] = []
    /// Where the prompter was before its last big jump, until reading continues
    /// from the new spot. If the speaker keeps reading near the old spot instead,
    /// the jump was wrong (a phrase that also appears later) and is undone.
    private var jumpedFrom: Int?
    /// Where the last big jump landed; reading this many words past it confirms it.
    private var jumpLanding = 0
    private let confirmJumpAfter = 10
    /// A move of more than this many words counts as a big jump.
    private let bigJump = 12

    func setScript(_ text: String) {
        script = text
        (tokens, tokenRanges) = Self.tokenize(text)
        let nsText = text as NSString
        rawTokens = tokenRanges.map { nsText.substring(with: $0) }
        totalTokens = tokens.count
        currentWordIndex = 0
        currentCharOffset = 0
        lastRecognizedWordCount = 0
        recentCandidates = []
        jumpedFrom = nil
        Logger.shared.log("TranscriptionMatcher.setScript — \(tokens.count) tokens")
    }

    /// The script word at `index` as written, for logs and test results.
    func word(at index: Int) -> String {
        rawTokens.indices.contains(index) ? rawTokens[index] : ""
    }

    func reset() {
        currentWordIndex = 0
        currentCharOffset = 0
        lastRecognizedWordCount = 0
        recentCandidates = []
        jumpedFrom = nil
    }

    /// Distinctive upcoming script words (five letters or more, up to `limit`),
    /// passed to speech recognition so names and jargon are heard correctly.
    func upcomingHintWords(limit: Int = 50) -> [String] {
        var seen = Set<String>()
        var words: [String] = []
        for i in currentWordIndex..<rawTokens.count where words.count < limit {
            let word = rawTokens[i]
            guard word.count >= 5, seen.insert(word.lowercased()).inserted else { continue }
            words.append(word)
        }
        return words
    }

    /// Manually override the current position (e.g. user hit arrow keys).
    func setCurrentIndex(_ index: Int) {
        let clamped = max(0, min(tokens.count, index))
        currentWordIndex = clamped
        recentCandidates = []
        if clamped > 0, clamped - 1 < tokenRanges.count {
            currentCharOffset = tokenRanges[clamped - 1].location
        } else {
            currentCharOffset = 0
        }
    }

    /// Ingest the latest recognized text. Called with the full transcription
    /// so far each time (recognizer returns cumulative partials).
    func ingest(_ recognizedText: String) {
        guard !tokens.isEmpty else { return }
        let recognizedWords = Self.tokenizeSimple(recognizedText)

        // We only need to consider recent words we haven't already consumed.
        // Grab the last few words of the new portion, plus a bit of overlap to
        // make matching more robust (enough for the wider search's phrase).
        let newStart = max(0, recognizedWords.count - widePhraseSize)
        guard newStart < recognizedWords.count else { return }
        let recent = Array(recognizedWords[newStart..<recognizedWords.count])

        // Only consider forward progress (never backtrack).
        let windowStart = currentWordIndex
        let windowEnd = min(tokens.count, windowStart + lookAhead)
        guard windowStart < windowEnd else { return }
        let window = Array(tokens[windowStart..<windowEnd])

        var match = Self.findBestPhraseMatch(
            recent: recent,
            window: window,
            phraseSize: phraseSize,
            minWordSim: minWordSimilarity,
            minPhraseSim: minPhraseSimilarity
        ).map { windowStart + $0 }
        // Script and speech often differ by a word (a typo, a paraphrase): accept
        // 4 of the last 5 heard words in order, for short moves only; it's too
        // loose to trust for jumps
        if match == nil, recent.count >= 5 {
            match = Self.findInOrderMatch(
                needle: Array(recent.suffix(5)), tokens: tokens, from: windowStart,
                to: min(windowEnd, windowStart + bigJump), minMatched: 4, minWordSim: minWordSimilarity, minLetters: 1
            )
        }
        let nearby = match != nil
        // Nothing nearby just after a big jump: maybe the speaker is still reading
        // where the prompter was, and the jump should be undone
        if match == nil, let from = jumpedFrom {
            let end = min(tokens.count, from + lookAhead)
            if from < end {
                match = Self.findBestPhraseMatch(
                    recent: recent, window: Array(tokens[from..<end]), phraseSize: phraseSize,
                    minWordSim: minWordSimilarity, minPhraseSim: minPhraseSimilarity
                ).map { from + $0 }
            }
        }
        // Nothing nearby: the reader may have skipped further ahead than the window.
        // Unless the words fit what was just read (recognition repeats words
        // already matched, and a phrase can appear twice in a script).
        if match == nil, recent.count >= wideMinMatched, windowEnd < tokens.count {
            let behindStart = max(0, windowStart - lookBehind)
            let alreadyRead = Self.findInOrderMatch(
                needle: recent, tokens: tokens, from: behindStart, to: min(tokens.count, windowStart + smallStep),
                minMatched: wideMinMatched, minWordSim: wideMinWordSimilarity
            )
            if alreadyRead == nil {
                match = Self.findInOrderMatch(
                    needle: recent, tokens: tokens, from: windowStart, to: tokens.count,
                    minMatched: wideMinMatched, minWordSim: wideMinWordSimilarity
                )
            }
        }

        if let newIndex = match {
            let undoing = jumpedFrom != nil && newIndex < currentWordIndex
            guard newIndex > currentWordIndex || undoing else { return }
            // Agreement: an earlier result, with fewer words heard, pointed at the same
            // spot or a few words before it. Recognition often repeats a result
            // unchanged, and a repeat shouldn't confirm a stray match on its own.
            let heardWords = recognizedWords.count
            let agreed = recentCandidates.contains {
                $0.index <= newIndex + 2 && $0.index >= newIndex - 8 && $0.heardWords != heardWords
            }
            recentCandidates = Array((recentCandidates + [(newIndex, heardWords)]).suffix(3))
            let smallStepForward = !undoing && newIndex - currentWordIndex <= smallStep
            if smallStepForward || agreed {
                if undoing {
                    Logger.shared.log("TranscriptionMatcher: undoing jump, back to word \(newIndex)")
                    jumpedFrom = nil
                } else if newIndex - currentWordIndex > bigJump {
                    // Chained jumps keep the original spot to come back to
                    jumpedFrom = jumpedFrom ?? currentWordIndex
                    jumpLanding = newIndex
                } else if nearby, newIndex >= jumpLanding + confirmJumpAfter {
                    jumpedFrom = nil  // reading carries on from the new spot
                }
                currentWordIndex = newIndex
                if newIndex - 1 < tokenRanges.count {
                    currentCharOffset = tokenRanges[newIndex - 1].location
                }
                lastRecognizedWordCount = recognizedWords.count
            }
        }
    }

    // MARK: - Static helpers

    static func tokenize(_ text: String) -> (tokens: [String], ranges: [NSRange]) {
        var tokens: [String] = []
        var ranges: [NSRange] = []
        let nsText = text as NSString
        let length = nsText.length
        let open = unichar(UInt8(ascii: "[")), close = unichar(UInt8(ascii: "]"))
        var depth = 0
        var i = 0
        while i < length {
            // Skip whitespace / non-word, and anything inside [brackets].
            while i < length, depth > 0 || !isWordChar(nsText.character(at: i)) {
                let c = nsText.character(at: i)
                if c == open, nsText.range(of: "]", range: NSRange(location: i, length: length - i)).location != NSNotFound {
                    depth += 1  // a stray "[" with no closing bracket is ignored
                } else if c == close {
                    depth = max(0, depth - 1)
                }
                i += 1
            }
            let start = i
            while i < length, isWordChar(nsText.character(at: i)) {
                i += 1
            }
            if i > start {
                let range = NSRange(location: start, length: i - start)
                let raw = nsText.substring(with: range)
                tokens.append(raw.lowercased())
                ranges.append(range)
            }
        }
        return (tokens, ranges)
    }

    static func tokenizeSimple(_ text: String) -> [String] {
        text.lowercased()
            .split { !($0.isLetter || $0.isNumber || $0 == "'") }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func isWordChar(_ c: unichar) -> Bool {
        let scalar = Unicode.Scalar(c)
        guard let s = scalar else { return false }
        return CharacterSet.letters.contains(s) ||
               CharacterSet.decimalDigits.contains(s) ||
               s == "'"
    }

    /// Find the best position in `window` where the last words of `recent` match.
    /// Returns the index ONE PAST the last matched word in `window` (i.e. the
    /// new position to advance to), or nil if no good match.
    /// (Used for the nearby window; the wider search uses `findInOrderMatch`.)
    static func findBestPhraseMatch(
        recent: [String],
        window: [String],
        phraseSize: Int,
        minWordSim: Float,
        minPhraseSim: Float
    ) -> Int? {
        guard !recent.isEmpty, !window.isEmpty else { return nil }

        // Use up to the last `phraseSize` recent words as the needle.
        let needle = Array(recent.suffix(phraseSize))
        let needleLen = needle.count

        var bestScore: Float = 0
        var bestEndIndex: Int? = nil

        // Slide the needle across the window; for short needles (e.g. 1-2 words
        // because recognition just started) we still allow single-word matching.
        for windowStart in 0..<window.count {
            let end = min(window.count, windowStart + needleLen)
            let slice = Array(window[windowStart..<end])
            guard slice.count == needle.count else { continue }

            // Compute per-word similarities; reject if any single word is poor.
            var sum: Float = 0
            var allGood = true
            for i in 0..<needleLen {
                let sim = similarity(needle[i], slice[i])
                if sim < minWordSim {
                    allGood = false
                    break
                }
                sum += sim
            }
            guard allGood else { continue }
            let avg = sum / Float(needleLen)
            if avg > bestScore {
                bestScore = avg
                bestEndIndex = windowStart + needleLen
            }
        }

        guard let idx = bestEndIndex, bestScore >= minPhraseSim else { return nil }
        return idx
    }

    /// Normalized similarity 0..1 (1 = identical). Levenshtein-based.
    /// Finds where in `tokens[from..<to]` the needle's words appear in order, at
    /// least `minMatched` of them, within a stretch a little longer than the needle,
    /// ending on a word that matches one of the needle's last two words. Returns the
    /// index just past the best stretch (most words matched, then the earliest).
    static func findInOrderMatch(
        needle: [String], tokens: [String], from: Int, to: Int, minMatched: Int, minWordSim: Float, minLetters: Int = 4
    ) -> Int? {
        guard from < to, needle.count >= minMatched else { return nil }
        let span = needle.count + 2
        let tail = needle.suffix(2)
        var best: (count: Int, end: Int)?
        for end in from..<to {
            guard tail.contains(where: { similarity($0, tokens[end]) >= minWordSim }) else { continue }
            let slice = Array(tokens[max(from, end - span + 1)...end])
            let count = inOrderCount(needle, slice, minWordSim: minWordSim, minLetters: minLetters)
            if count >= minMatched, count > (best?.count ?? 0) {
                best = (count, end)
            }
        }
        return best.map { $0.end + 1 }
    }

    /// How many words of `minLetters` letters or more from `a` appear in `b` in the
    /// same order (fuzzy-equal), allowing words in between on either side.
    static func inOrderCount(_ a: [String], _ b: [String], minWordSim: Float, minLetters: Int = 4) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var row = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            let weight = x.count >= minLetters ? 1 : 0
            var diagonal = 0
            for j in 1...b.count {
                let above = row[j]
                let matched = similarity(x, b[j - 1]) >= minWordSim ? diagonal + weight : 0
                row[j] = max(matched, row[j], row[j - 1])
                diagonal = above
            }
        }
        return row[b.count]
    }

    static func similarity(_ a: String, _ b: String) -> Float {
        if a == b { return 1 }
        let maxLen = max(a.count, b.count)
        if maxLen == 0 { return 1 }
        let dist = Self.editDistance(a, b)
        return max(0, 1 - Float(dist) / Float(maxLen))
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }
        var prev = Array(0...bChars.count)
        var curr = Array(repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            curr[0] = i
            for j in 1...bChars.count {
                if aChars[i - 1] == bChars[j - 1] {
                    curr[j] = prev[j - 1]
                } else {
                    curr[j] = 1 + min(prev[j], curr[j - 1], prev[j - 1])
                }
            }
            swap(&prev, &curr)
        }
        return prev[bChars.count]
    }
}
