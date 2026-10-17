#if DEBUG
import AVFoundation
import Foundation

/// Debug-only test runs: instead of the microphone, an audio file is played
/// straight into speech recognition in real time, and the prompter's position
/// is recorded so a run can be checked against the script afterwards.
///
///     Offscript --test-audio A.m4a --test-script S.txt [--test-results DIR]
///               [--test-aloud] [--test-hidden] [--test-quit]
///
/// The sandboxed debug build can read and write only ~/Projects/offscript/test-audio/
/// (see Cue-Debug.entitlements), so the files live there.
struct TestRun {
    let audioURL: URL
    let scriptURL: URL
    let resultsDir: URL
    /// Play the audio through the speakers too, to watch along.
    let aloud: Bool
    /// Keep the window invisible and leave focus alone, for unattended runs.
    let hidden: Bool
    /// Quit when the audio ends, after writing results.
    let quitWhenDone: Bool

    static let current: TestRun? = TestRun(arguments: CommandLine.arguments)

    init?(arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        guard let audio = value("--test-audio"), let script = value("--test-script") else { return nil }
        audioURL = URL(fileURLWithPath: audio)
        scriptURL = URL(fileURLWithPath: script)
        resultsDir = value("--test-results").map { URL(fileURLWithPath: $0) } ?? audioURL.deletingLastPathComponent()
        aloud = arguments.contains("--test-aloud")
        hidden = arguments.contains("--test-hidden")
        quitWhenDone = arguments.contains("--test-quit")
    }

    var name: String { scriptURL.deletingPathExtension().lastPathComponent }
}

/// Reads a file and hands it to `onBuffer` in tenth-of-a-second chunks at
/// playback speed. No audio device is involved, so switching outputs (say,
/// connecting AirPods) can't stall a run. With `aloud`, a separate player
/// also plays it through the speakers.
final class AudioFileFeeder {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onFinish: (() -> Void)?

    private let queue = DispatchQueue(label: "com.san.Cue.testfeeder", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var speaker: AVAudioPlayer?

    func start(url: URL, aloud: Bool) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let chunk = AVAudioFrameCount(format.sampleRate / 10)
        Logger.shared.log("TestRun: feeding \(url.lastPathComponent), \(Int(Double(file.length) / format.sampleRate))s")
        if aloud {
            speaker = try AVAudioPlayer(contentsOf: url)
            speaker?.play()
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk),
                  (try? file.read(into: buffer, frameCount: chunk)) != nil,
                  buffer.frameLength > 0 else {
                self.timer?.cancel()
                self.timer = nil
                DispatchQueue.main.async { self.onFinish?() }
                return
            }
            self.onBuffer?(buffer)
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        speaker?.stop()
        speaker = nil
    }
}

/// Collects position changes and what was heard, then writes two files:
/// `<script>-positions.csv` (seconds, word index, total words, word) and
/// `<script>-heard.jsonl` (one line per recognition result: seconds and the
/// full text), which the replay tests in CueTests feed back into the matcher.
final class TestRecorder {
    private let run: TestRun
    private var start: Date?
    private var positions = ["seconds,word_index,total_words,word"]
    private var heard: [String] = []

    init(run: TestRun) { self.run = run }

    func begin() { start = Date() }

    private var elapsed: String {
        String(format: "%.1f", start.map { Date().timeIntervalSince($0) } ?? 0)
    }

    func position(_ index: Int, total: Int, word: String) {
        guard start != nil else { return }
        positions.append("\(elapsed),\(index),\(total),\(word.replacingOccurrences(of: ",", with: ""))")
    }

    func heard(_ text: String) {
        guard let start else { return }
        let line: [String: Any] = ["t": (Date().timeIntervalSince(start) * 100).rounded() / 100, "text": text]
        if let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            heard.append(json)
        }
    }

    func write() {
        do {
            try FileManager.default.createDirectory(at: run.resultsDir, withIntermediateDirectories: true)
            try positions.joined(separator: "\n").write(to: run.resultsDir.appendingPathComponent("\(run.name)-positions.csv"), atomically: true, encoding: .utf8)
            try heard.joined(separator: "\n").write(to: run.resultsDir.appendingPathComponent("\(run.name)-heard.jsonl"), atomically: true, encoding: .utf8)
            Logger.shared.log("TestRun: results written to \(run.resultsDir.path)")
        } catch {
            Logger.shared.log("TestRun: couldn't write results: \(error.localizedDescription)")
        }
    }
}
#endif
