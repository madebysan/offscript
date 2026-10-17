import AppKit
import AVFoundation
import Speech

/// Microphone and Speech Recognition access, shared by the window and the menu bar.
///
/// The prompts are asked one at a time, microphone first, each only after the
/// previous one is answered: two requests at once, or a request made while the
/// menu bar menu is still closing, can leave a prompt that never appears.
final class Permissions: ObservableObject {
    static let shared = Permissions()

    enum Kind {
        case microphone, speech

        var name: String { self == .microphone ? "Microphone" : "Speech Recognition" }

        var settingsURL: URL {
            let pane = self == .microphone ? "Privacy_Microphone" : "Privacy_SpeechRecognition"
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        }
    }

    enum State: Equatable {
        case notDetermined, granted, denied, restricted
    }

    @Published private(set) var microphone: State = .notDetermined
    @Published private(set) var speech: State = .notDetermined
    @Published private(set) var isRequesting = false

    private var waiting: [(Bool) -> Void] = []
    private var observer: NSObjectProtocol?

    private init() {
        refresh()
        Logger.shared.log("Permissions: microphone=\(microphone), speech=\(speech)")
        // Pick up changes made in System Settings when the user comes back
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    var allGranted: Bool { microphone == .granted && speech == .granted }

    /// Permissions the user turned off (or a profile blocks); asking again won't show a prompt.
    var blocked: [Kind] {
        [(Kind.microphone, microphone), (Kind.speech, speech)]
            .filter { $0.1 == .denied || $0.1 == .restricted }
            .map(\.0)
    }

    func state(of kind: Kind) -> State { kind == .microphone ? microphone : speech }

    func refresh() {
        microphone = Self.state(AVCaptureDevice.authorizationStatus(for: .audio))
        speech = Self.state(SFSpeechRecognizer.authorizationStatus())
    }

    /// Asks for whatever hasn't been decided yet and calls back on main with
    /// whether both are granted. `fromMenu` waits for the menu to close first.
    func request(fromMenu: Bool = false, _ completion: @escaping (Bool) -> Void = { _ in }) {
        refresh()
        if microphone != .notDetermined && speech != .notDetermined {
            completion(allGranted)
            return
        }
        waiting.append(completion)
        guard !isRequesting else { return }
        isRequesting = true
        let delay: TimeInterval = fromMenu ? 0.3 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.askMicrophone()
        }
    }

    func openSettings(for kind: Kind) {
        NSWorkspace.shared.open(kind.settingsURL)
    }

    // MARK: - Private

    private func askMicrophone() {
        guard microphone == .notDetermined else { askSpeech(); return }
        Logger.shared.log("Permissions: asking for microphone")
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                Logger.shared.log("Permissions: microphone granted=\(granted)")
                self.refresh()
                if granted { self.askSpeech() } else { self.finish() }
            }
        }
    }

    private func askSpeech() {
        guard speech == .notDetermined else { finish(); return }
        Logger.shared.log("Permissions: asking for speech recognition")
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { [weak self] in
                Logger.shared.log("Permissions: speech status=\(status.rawValue)")
                self?.refresh()
                self?.finish()
            }
        }
    }

    private func finish() {
        isRequesting = false
        let callbacks = waiting
        waiting = []
        callbacks.forEach { $0(allGranted) }
    }

    private static func state(_ status: AVAuthorizationStatus) -> State {
        switch status {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    private static func state(_ status: SFSpeechRecognizerAuthorizationStatus) -> State {
        switch status {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
}
