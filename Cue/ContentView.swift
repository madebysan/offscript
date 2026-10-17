import AppKit
import Speech
import SwiftUI

struct ContentView: View {
    @AppStorage("defaultTextSize") private var textSize: Double = 18
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.92
    @AppStorage("fontFamily") private var fontFamily: String = PrompterFont.system
    @AppStorage("theme") private var themeChoice: PrompterTheme = .dark
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject private var library = ScriptLibrary.shared
    @ObservedObject private var permissions = Permissions.shared
    @StateObject private var mic = MicLevelMonitor()
    @StateObject private var speech = SpeechTranscriber()
    @StateObject private var matcher = TranscriptionMatcher()

    @State private var countdown: Int? = nil
    @State private var isRunning: Bool = false
    @State private var editorFocused: Bool = false
    @State private var showingAppearance: Bool = false
    #if DEBUG
    @State private var testFeeder: AudioFileFeeder?
    @State private var testRecorder: TestRecorder?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            ZStack(alignment: .top) {
                TeleprompterView(
                    text: Binding(get: { library.text }, set: { library.edit($0) }),
                    font: PrompterFont.font(PrompterFont.choice(fontFamily), size: textSize),
                    textColor: theme.text,
                    focusCharOffset: focusOffset,
                    onFocusChange: { editorFocused = $0 }
                )
                .onChange(of: library.text) { _, newText in
                    matcher.setScript(newText)
                }

                if let count = countdown, count > 0 {
                    CountdownView(value: count, background: Color(nsColor: theme.background), foreground: Color(nsColor: theme.text))
                }

                if !permissions.blocked.isEmpty {
                    permissionHint
                }
            }
        }
        .background(
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 0, bottomLeading: 18, bottomTrailing: 18, topTrailing: 0)
            )
            .fill(Color(nsColor: theme.background).opacity(backgroundOpacity))
        )
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 0, bottomLeading: 18, bottomTrailing: 18, topTrailing: 0)
            )
        )
        .onAppear {
            matcher.setScript(library.text)
            hookUpMicToSpeech()
            AppDelegate.onSpacePressed = { togglePlay() }
            AppDelegate.onEscapePressed = { pauseEverything() }
            AppDelegate.onArrowUp = { manualScroll(by: -80) }
            AppDelegate.onArrowDown = { manualScroll(by: 80) }
            AppDelegate.isEditorFocused = { editorFocused }
            AppDelegate.shared?.panel?.appearance = themeChoice.appearance
            #if DEBUG
            // Lets screenshots check the popover without clicking
            if CommandLine.arguments.contains("--qa-appearance") { showingAppearance = true }
            if let run = TestRun.current { prepareTestRun(run) }
            // README screenshot: show the prompter mid-read, without the microphone
            if CommandLine.arguments.contains("--screenshots") {
                matcher.setCurrentIndex(64)
                isRunning = true
            }
            #endif
        }
        .onChange(of: themeChoice) { _, choice in
            AppDelegate.shared?.panel?.appearance = choice.appearance
        }
        #if DEBUG
        .onChange(of: matcher.currentWordIndex) { _, index in
            testRecorder?.position(index, total: matcher.totalTokens, word: matcher.word(at: index - 1))
        }
        #endif
        .onChange(of: editorFocused) { _, f in
            AppDelegate.isEditorFocused = { f }
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 10) {
            Button(action: togglePlay) {
                Image(systemName: playSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help(playHelp)

            Button(action: resetProgress) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Reset to start")

            if isRunning {
                Text("\(matcher.currentWordIndex)/\(matcher.totalTokens)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            scriptsMenu

            Divider().frame(height: 12)

            HStack(spacing: 4) {
                Image(systemName: "textformat.size")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Slider(value: $textSize, in: 12...72).frame(width: 120)
            }
            .help("Text size")

            Button { showingAppearance.toggle() } label: {
                Image(systemName: "paintpalette")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Font, theme and opacity")
            .popover(isPresented: $showingAppearance, arrowEdge: .bottom) {
                AppearanceControls()
                    .padding(16)
                    .frame(width: 320)
            }

            Spacer()

            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close (⌘Q)")
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    /// Recent scripts, a new script and the practice script.
    private var scriptsMenu: some View {
        Menu {
            Button("New Script") { switchScript { library.newScript() } }
            if !library.others.isEmpty {
                Section("Recent") {
                    ForEach(library.others) { script in
                        Button(script.title) { switchScript { library.open(script.id) } }
                    }
                }
            }
            Divider()
            Button("Practice Script") { switchScript { library.openPractice() } }
                .disabled(library.isPractice)
        } label: {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Scripts")
    }

    /// Shown when the microphone or speech recognition is turned off for Offscript.
    private var permissionHint: some View {
        let blocked = permissions.blocked
        let names = blocked.map(\.name).joined(separator: " and ")
        return HStack(spacing: 10) {
            Image(systemName: "mic.slash.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Offscript can't hear you")
                    .font(.callout.weight(.semibold))
                Text("Turn on Offscript under \(names) in Privacy & Security.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button("Open Settings") {
                if let first = blocked.first { permissions.openSettings(for: first) }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: theme.background).opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.3)))
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// The chosen theme, with Match System resolved to light or dark.
    private var theme: PrompterTheme { themeChoice.resolved(for: colorScheme) }

    private var playSymbol: String {
        if countdown != nil { return "stop.fill" }
        return isRunning ? "pause.fill" : "play.fill"
    }

    private var playHelp: String {
        if isRunning || countdown != nil { return "Pause (Space)" }
        return "Start (Space)"
    }

    private var focusOffset: Int? {
        // Scroll to the current matched position while running; otherwise let the user control.
        guard isRunning, !editorFocused else { return nil }
        return matcher.currentCharOffset
    }

    // MARK: - Actions

    private func togglePlay() {
        Logger.shared.log("togglePlay — isRunning=\(isRunning) micRunning=\(mic.isRunning) countdown=\(countdown.map(String.init) ?? "nil") editorFocused=\(editorFocused)")
        if countdown != nil {
            withAnimation(.easeInOut(duration: 0.2)) { countdown = nil }
            return
        }
        if isRunning {
            stopRunning()
            return
        }
        // Ask for the microphone and speech recognition first; the countdown
        // starts once both are allowed.
        guard permissions.allGranted else {
            permissions.request { granted in
                if granted { startMicAndCountdown() }
            }
            return
        }
        startMicAndCountdown()
    }

    private func startMicAndCountdown() {
        guard countdown == nil, !isRunning else { return }
        if !mic.isRunning { mic.start() }
        startWithCountdown()
    }

    private func pauseEverything() {
        stopRunning()
        withAnimation(.easeInOut(duration: 0.2)) { countdown = nil }
    }

    private func resetProgress() {
        // Defensive: stop any in-flight speech/scroll first so we don't reset
        // position while an update is mid-flight (can confuse SwiftUI layout).
        Logger.shared.log("resetProgress")
        stopRunning()
        withAnimation(.easeInOut(duration: 0.2)) { countdown = nil }
        matcher.reset()
    }

    /// Stops following before another script replaces the one on screen.
    private func switchScript(_ change: () -> Void) {
        pauseEverything()
        change()
    }

    private func startWithCountdown() {
        Logger.shared.log("startWithCountdown — setting countdown=3")
        countdown = 3
        Logger.shared.log("countdown set, scheduling tick")
        tickCountdown()
    }

    private func tickCountdown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let c = countdown else { return }
            if c > 1 {
                withAnimation(.easeInOut(duration: 0.2)) { countdown = c - 1 }
                tickCountdown()
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { countdown = nil }
                beginRunning()
            }
        }
    }

    private func beginRunning() {
        isRunning = true
        speech.start()
        Logger.shared.log("beginRunning")
        #if DEBUG
        if let run = TestRun.current { startTestAudio(run) }
        #endif
    }

    private func stopRunning() {
        if isRunning {
            Logger.shared.log("stopRunning")
        }
        isRunning = false
        speech.stop()
        // Keep mic running between sessions so the orange dot stays consistent
        // and play→speech starts instantly. User quitting the app stops it.
    }

    private func hookUpMicToSpeech() {
        let speechRef = speech
        let matcherRef = matcher
        mic.onSampleBuffer = { sb in
            speechRef.append(sampleBuffer: sb)
        }
        speech.onRecognized = { text in
            matcherRef.ingest(text)
        }
        speech.hintWords = { matcherRef.upcomingHintWords() }
        Logger.shared.log("hookUpMicToSpeech — mic.onSampleBuffer set=\(mic.onSampleBuffer != nil), speech.onRecognized set=\(speech.onRecognized != nil)")
    }

    private func manualScroll(by delta: CGFloat) {
        // When user hits arrows, we nudge the matcher's position by N tokens
        // so the auto-follow doesn't immediately yank it back.
        let tokensPerStep = delta > 0 ? 5 : -5
        let newIndex = max(0, min(matcher.totalTokens, matcher.currentWordIndex + tokensPerStep))
        Logger.shared.log("manualScroll delta=\(delta) → word \(newIndex)")
        matcher.setCurrentIndex(newIndex)
    }

    // MARK: - Debug test runs

    #if DEBUG
    /// Loads the test script, then starts like Play, without the microphone.
    private func prepareTestRun(_ run: TestRun) {
        guard let text = try? String(contentsOf: run.scriptURL, encoding: .utf8) else {
            Logger.shared.log("TestRun: couldn't read \(run.scriptURL.path)")
            return
        }
        library.edit(text)
        matcher.setScript(library.text)
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    Logger.shared.log("TestRun: speech recognition not allowed (\(status.rawValue))")
                    return
                }
                startWithCountdown()
            }
        }
    }

    private func startTestAudio(_ run: TestRun) {
        let recorder = TestRecorder(run: run)
        let feeder = AudioFileFeeder()
        let speechRef = speech
        let matcherRef = matcher
        feeder.onBuffer = { speechRef.append(buffer: $0) }
        feeder.onFinish = { finishTestRun(run) }
        speech.onRecognized = { text in
            matcherRef.ingest(text)
            recorder.heard(text)
        }
        testRecorder = recorder
        testFeeder = feeder
        recorder.begin()
        do {
            try feeder.start(url: run.audioURL, aloud: run.aloud)
        } catch {
            Logger.shared.log("TestRun: couldn't play \(run.audioURL.path): \(error.localizedDescription)")
            finishTestRun(run)
        }
    }

    private func finishTestRun(_ run: TestRun) {
        testFeeder?.stop()
        testFeeder = nil
        // Let the last recognition results arrive before stopping
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            stopRunning()
            testRecorder?.write()
            testRecorder = nil
            if run.quitWhenDone { NSApp.terminate(nil) }
        }
    }
    #endif
}

#Preview {
    ContentView()
        .frame(width: 520, height: 340)
}
