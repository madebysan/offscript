import AVFoundation
import Foundation
import Speech

final class SpeechTranscriber: ObservableObject {
    // Only isRunning is observed. Per-partial fields are plain vars.
    @Published private(set) var isRunning: Bool = false

    private(set) var lastRecognized: String = ""
    private(set) var lastError: String?
    private(set) var bufferCount: Int = 0

    /// Called every time new recognized text is available.
    /// Invoked on main queue.
    var onRecognized: ((String) -> Void)?
    /// Upcoming script words, passed to each new session as recognition hints
    /// so names and jargon in the script are heard correctly. Called on main.
    var hintWords: (() -> [String])?

    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    /// Held until a rolled-over session delivers its last result.
    private var retiringTask: SFSpeechRecognitionTask?
    private var internalBufferCount: Int = 0

    /// The current request. Read from the capture queue, replaced on main when a
    /// recognition session ends and a new one starts, so access goes through `lock`.
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private let lock = NSLock()

    /// Recognition runs on this Mac when supported; if on-device fails, Cue falls back
    /// to Apple's servers so following doesn't stop.
    private var useOnDevice = true
    /// Each recognition session gets a number so callbacks from an ended session are ignored.
    private var session = 0
    private var sessionHadResults = false
    /// A session replaced by a planned restart. Its last words still count,
    /// but its ending doesn't start another session.
    private var retiringSession = -1
    /// Server sessions end after about a minute, losing the words in the gap
    /// before a new one starts. Cue starts a fresh session a little before
    /// that while the microphone keeps feeding audio.
    private let sessionLength: TimeInterval = 55
    /// Sessions in a row that ended without recognizing anything; stops endless restarts.
    private var emptySessionsInARow = 0

    func start() {
        guard !isRunning else { return }

        let r = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let r else {
            lastError = "SFSpeechRecognizer init returned nil — locale may be unsupported"
            Logger.shared.log("SFSpeechRecognizer init returned nil")
            return
        }
        Logger.shared.log("SFSpeechRecognizer: isAvailable=\(r.isAvailable), supportsOnDevice=\(r.supportsOnDeviceRecognition), locale=\(r.locale.identifier)")
        guard r.isAvailable else {
            lastError = "speech recognizer not available"
            Logger.shared.log("SFSpeechRecognizer unavailable")
            return
        }
        recognizer = r
        useOnDevice = r.supportsOnDeviceRecognition
        emptySessionsInARow = 0
        internalBufferCount = 0
        isRunning = true
        beginSession()
    }

    /// Starts a recognition session. Apple ends sessions on its own (server sessions
    /// after about a minute, any session after a long pause or an error), so a new
    /// one starts whenever one ends while Cue is still running.
    private func beginSession() {
        guard isRunning, let recognizer else { return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = useOnDevice
        req.taskHint = .dictation
        req.contextualStrings = hintWords?() ?? []
        lock.lock()
        request = req
        lock.unlock()

        session += 1
        let thisSession = session
        sessionHadResults = false
        Logger.shared.log("Speech session \(thisSession) started (onDevice=\(useOnDevice), hints=\(req.contextualStrings.count))")
        DispatchQueue.main.asyncAfter(deadline: .now() + sessionLength) { [weak self] in
            self?.rollOver(from: thisSession)
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                #if DEBUG
                Logger.shared.log("RECOGNIZED (isFinal=\(result.isFinal)): \"\(text)\"")
                #endif
                DispatchQueue.main.async {
                    guard thisSession == self.session || thisSession == self.retiringSession else { return }
                    if thisSession == self.session { self.sessionHadResults = true }
                    self.lastRecognized = text
                    self.onRecognized?(text)
                }
            }
            if let error {
                Logger.shared.log("SFSpeech task error: \(error.localizedDescription) — code=\((error as NSError).code)")
                DispatchQueue.main.async {
                    guard thisSession == self.session else { return }
                    self.lastError = error.localizedDescription
                }
            }
            if error != nil || result?.isFinal == true {
                DispatchQueue.main.async {
                    self.sessionEnded(thisSession, failed: error != nil)
                }
            }
        }
    }

    /// Planned restart: the current request stops taking audio and finishes,
    /// and a new session takes over the microphone at once.
    private func rollOver(from rollingSession: Int) {
        guard isRunning, rollingSession == session else { return }
        Logger.shared.log("Speech session \(rollingSession) rolling over")
        retiringSession = rollingSession
        retiringTask = task
        lock.lock()
        let old = request
        lock.unlock()
        beginSession()
        old?.endAudio()
    }

    private func sessionEnded(_ endedSession: Int, failed: Bool) {
        guard isRunning, endedSession == session else { return }

        if sessionHadResults {
            emptySessionsInARow = 0
        } else {
            emptySessionsInARow += 1
            // On-device recognition that fails without hearing anything: use the server instead
            if failed && useOnDevice {
                useOnDevice = false
                Logger.shared.log("On-device recognition failed; falling back to server")
            }
        }
        if emptySessionsInARow >= 5 {
            Logger.shared.log("Speech recognition keeps failing; stopping")
            stop()
            return
        }

        lock.lock()
        request?.endAudio()
        lock.unlock()
        // A short pause after repeated empty sessions avoids a tight restart loop
        let delay = emptySessionsInARow > 1 ? 0.5 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.beginSession()
        }
    }

    /// Feed a CMSampleBuffer straight from AVCaptureAudioDataOutput.
    /// Safe to call from the capture queue.
    func append(sampleBuffer: CMSampleBuffer) {
        lock.lock()
        let req = request
        lock.unlock()
        guard let req else { return }
        req.appendAudioSampleBuffer(sampleBuffer)
        internalBufferCount += 1
        if internalBufferCount == 1 || internalBufferCount % 100 == 0 {
            let count = internalBufferCount
            Logger.shared.log("speech sample buffer #\(count) appended (numSamples=\(CMSampleBufferGetNumSamples(sampleBuffer)))")
            DispatchQueue.main.async { [weak self] in self?.bufferCount = count }
        }
    }

    /// Feed audio from a file in debug test runs. Safe to call from any queue.
    func append(buffer: AVAudioPCMBuffer) {
        lock.lock()
        let req = request
        lock.unlock()
        req?.append(buffer)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        session += 1 // ignore callbacks from the session being cancelled
        lock.lock()
        request?.endAudio()
        request = nil
        lock.unlock()
        task?.finish()
        task = nil
        retiringTask?.cancel()
        retiringTask = nil
        recognizer = nil
        Logger.shared.log("SpeechTranscriber stopped")
    }
}
