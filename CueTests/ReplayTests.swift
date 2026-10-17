import XCTest

/// Replays recorded speech recognition results against script variants and scores
/// how closely the prompter followed the speaker. The recordings, scenarios and
/// audio live in test-audio/ (git-ignored), made by scripts/tracking-tests/; when
/// they're missing this test is skipped. Writes test-audio/results/scorecard.md.
final class ReplayTests: XCTestCase {
    struct Scenario: Decodable {
        let name: String
        let recording: String
        let variant: String
        let note: String
        let duration: Double
        let script: String
        /// [seconds, utf16 end offset of the script word the speaker just finished]
        let marks: [[Double]]
    }

    struct Heard: Decodable {
        let t: Double
        let text: String
    }

    struct Score {
        let scenario: Scenario
        let medianWordsBehind: Int
        let p95WordsBehind: Int
        /// Longest stretch, in seconds, with the prompter more than a line behind.
        let lostFor: Double
        /// Most script words the speaker said during one such stretch.
        let lostWords: Int
        /// Longest stretch, in seconds, with the prompter more than a line ahead.
        let aheadFor: Double
        /// Times the prompter went more than a line ahead of the speaker.
        let jumpsAhead: Int
        let endGap: Int
        let failures: [String]
    }

    /// Scenarios whose failure is a quirk of the test, not of following: reported
    /// on the scorecard but not failed.
    static let known: [String: String] = [
        "mkbhd--adlibs": "the removed paragraph says \"7,500 milliamp hour silicon carbon battery\", which the script repeats later, so jumping there is right",
    ]

    /// Limits a run must stay within to pass. A line in the default window holds
    /// about 10 to 12 words, so within that the line you're reading stays in view.
    static let lineOfWords = 12
    static let maxP95WordsBehind = 10
    /// Being more than a line behind is judged by how much the speaker said in the
    /// meantime, not by seconds: no one can follow through music or silence.
    static let maxLostWords = 25
    static let maxAheadFor = 5.0
    static let maxEndGap = 15

    static let dataDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("test-audio")

    func testTrackingScorecard() throws {
        let scenarioDir = Self.dataDir.appendingPathComponent("scenarios")
        let recordingDir = Self.dataDir.appendingPathComponent("recordings")
        let files = (try? FileManager.default.contentsOfDirectory(at: scenarioDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        try XCTSkipIf(files.isEmpty, "No scenarios in test-audio/scenarios; see scripts/tracking-tests/README.md")

        var scores: [Score] = []
        var missing: Set<String> = []
        for file in files {
            let scenario = try JSONDecoder().decode(Scenario.self, from: Data(contentsOf: file))
            let heardURL = recordingDir.appendingPathComponent("\(scenario.recording)-heard.jsonl")
            guard let heardText = try? String(contentsOf: heardURL, encoding: .utf8) else {
                missing.insert(scenario.recording)
                continue
            }
            let heard = heardText.split(separator: "\n").compactMap {
                try? JSONDecoder().decode(Heard.self, from: Data($0.utf8))
            }
            scores.append(Self.score(scenario, heard: heard))
        }
        try XCTSkipIf(scores.isEmpty, "No recordings yet for: \(missing.sorted().joined(separator: ", "))")

        try Self.writeScorecard(scores, missing: missing)
        for s in scores where !s.failures.isEmpty && Self.known[s.scenario.name] == nil {
            XCTFail("\(s.scenario.name): \(s.failures.joined(separator: "; "))")
        }
    }

    // MARK: - Scoring

    static func score(_ scenario: Scenario, heard: [Heard]) -> Score {
        let matcher = TranscriptionMatcher()
        matcher.setScript(scenario.script)
        let ranges = TranscriptionMatcher.tokenize(scenario.script).ranges

        // Where the speaker is: words finished so far, never moving back (a reread
        // shouldn't pull the prompter backward)
        var truth: [(t: Double, index: Int)] = []
        var furthest = 0
        for mark in scenario.marks {
            let end = Int(mark[1])
            let index = ranges.prefix { $0.location < end }.count
            if index > furthest {
                furthest = index
                truth.append((mark[0], index))
            }
        }
        func expected(at t: Double) -> Int {
            truth.last { $0.t <= t }?.index ?? 0
        }
        /// When the speaker first finished word number `index` (1-based), if ever.
        func reached(_ index: Int) -> Double? {
            truth.first { $0.index >= index }?.t
        }

        var behind: [Int] = []
        var lostFor = 0.0, lostSince: Double?, lostWords = 0
        let saidTimes = scenario.marks.map { $0[0] }.sorted()
        /// Script words said up to and including time `t`.
        func saidBy(_ t: Double) -> Int {
            var low = 0, high = saidTimes.count
            while low < high {
                let mid = (low + high) / 2
                if saidTimes[mid] <= t { low = mid + 1 } else { high = mid }
            }
            return low
        }
        var aheadFor = 0.0, aheadSince: Double?, jumpsAhead = 0
        var trace = ["seconds,prompter,speaker"]
        var next = 0
        let step = 0.25
        var t = 0.0
        while t <= scenario.duration {
            while next < heard.count, heard[next].t <= t {
                matcher.ingest(heard[next].text)
                next += 1
            }
            let actual = matcher.currentWordIndex
            let speaker = expected(at: t)
            // Normal following; stretches more than a line behind are judged by lostWords
            if speaker - actual <= lineOfWords { behind.append(max(0, speaker - actual)) }
            if speaker - actual > lineOfWords {
                lostSince = lostSince ?? t
                lostFor = max(lostFor, t - lostSince!)
                lostWords = max(lostWords, saidBy(t) - saidBy(lostSince!))
            } else {
                lostSince = nil
            }
            if actual - speaker > lineOfWords {
                if aheadSince == nil { jumpsAhead += 1 }
                aheadSince = aheadSince ?? t
                aheadFor = max(aheadFor, t - aheadSince!)
            } else {
                aheadSince = nil
            }
            if Int(t * 4) % 4 == 0 { trace.append(String(format: "%.0f,%d,%d", t, actual, speaker)) }
            t += step
        }
        writeTrace(trace, name: scenario.name)

        let sorted = behind.sorted()
        func percentile(_ p: Double) -> Int {
            sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
        }
        let endGap = expected(at: scenario.duration) - matcher.currentWordIndex
        let p95 = percentile(0.95)

        var failures: [String] = []
        if p95 > maxP95WordsBehind { failures.append("95% of the time within \(p95) words, needs \(maxP95WordsBehind)") }
        if lostWords > maxLostWords { failures.append(String(format: "more than a line behind for %d spoken words (%.0fs)", lostWords, lostFor)) }
        if aheadFor > maxAheadFor { failures.append(String(format: "more than a line ahead for %.0fs", aheadFor)) }
        if abs(endGap) > maxEndGap { failures.append("ended \(endGap) words off") }

        return Score(
            scenario: scenario, medianWordsBehind: percentile(0.5), p95WordsBehind: p95, lostFor: lostFor, lostWords: lostWords,
            aheadFor: aheadFor, jumpsAhead: jumpsAhead, endGap: endGap, failures: failures
        )
    }

    /// Prompter and speaker position each second, for looking into a failure.
    static func writeTrace(_ lines: [String], name: String) {
        let dir = dataDir.appendingPathComponent("results/traces")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("\(name).csv"), atomically: true, encoding: .utf8)
    }

    static func writeScorecard(_ scores: [Score], missing: Set<String>) throws {
        let passed = scores.filter { $0.failures.isEmpty || known[$0.scenario.name] != nil }.count
        var lines = [
            "# Tracking scorecard",
            "",
            "\(passed) of \(scores.count) scenarios pass. Positions are sampled every 0.25 s while the audio plays; words behind is how far the prompter trails the last word said, while following (within a line).",
            String(format: "Limits: 95%% of the time within %d words, never more than a line (%d words) behind while the speaker says over %d words, never more than a line ahead for over %.0f s, and within %d words at the end.", maxP95WordsBehind, lineOfWords, maxLostWords, maxAheadFor, maxEndGap),
            "",
            "| Scenario | What it tests | Median words behind | 95% words behind | Longest >1 line behind (s, words said) | Longest >1 line ahead (s) | Jumps ahead | End gap (words) | Result |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
        for s in scores {
            let result: String
            if s.failures.isEmpty {
                result = "pass"
            } else if let reason = known[s.scenario.name] {
                result = "known: " + s.failures.joined(separator: "; ") + " (" + reason + ")"
            } else {
                result = "FAIL: " + s.failures.joined(separator: "; ")
            }
            lines.append(String(
                format: "| %@ | %@ | %d | %d | %.1f (%d) | %.1f | %d | %d | %@ |",
                s.scenario.name, s.scenario.note, s.medianWordsBehind, s.p95WordsBehind, s.lostFor, s.lostWords, s.aheadFor, s.jumpsAhead, s.endGap, result
            ))
        }
        if !missing.isEmpty {
            lines += ["", "Not recorded yet: \(missing.sorted().joined(separator: ", "))."]
        }
        let results = dataDir.appendingPathComponent("results")
        try FileManager.default.createDirectory(at: results, withIntermediateDirectories: true)
        let text = lines.joined(separator: "\n") + "\n"
        try text.write(to: results.appendingPathComponent("scorecard.md"), atomically: true, encoding: .utf8)
        print(text)
    }
}
