import AppKit
import AVFoundation
import Speech
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    var panel: NSPanel?
    var keyMonitor: Any?

    static var onSpacePressed: () -> Void = {}
    static var onEscapePressed: () -> Void = {}
    static var onArrowUp: () -> Void = {}
    static var onArrowDown: () -> Void = {}
    static var isEditorFocused: () -> Bool = { false }

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.log("applicationDidFinishLaunching")
        Logger.shared.log("bundle: \(Bundle.main.bundleIdentifier ?? "?"), executable: \(Bundle.main.executablePath ?? "?")")
        Logger.shared.log("home: \(FileManager.default.homeDirectoryForCurrentUser.path)")
        Updates.start()

        // No Dock icon (LSUIElement), but still activate the app so CoreAudio/TCC
        // routes mic input to us: macOS 26 doesn't reliably hand mic audio to
        // non-activating panels.
        #if DEBUG
        let testHidden = TestRun.current?.hidden == true
        #else
        let testHidden = false
        #endif
        if !testHidden { NSApp.activate(ignoringOtherApps: true) }

        let defaultSize = NSSize(width: 380, height: 100)
        let initialOrigin = Self.topCenterOrigin(for: defaultSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: initialOrigin, size: defaultSize),
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        #if DEBUG
        let qaVisible = CommandLine.arguments.contains("--qa-visible")
        let screenshots = CommandLine.arguments.contains("--screenshots")
        panel.sharingType = qaVisible || screenshots ? .readOnly : .none
        #else
        panel.sharingType = .none
        #endif
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 360, height: 90)
        #if DEBUG
        if screenshots {
            // README screenshot: a fixed size, an opaque dark window, and the saved
            // window position left alone
            panel.setFrame(NSRect(origin: Self.topCenterOrigin(for: Self.screenshotSize), size: Self.screenshotSize), display: false)
            panel.isOpaque = true
            panel.backgroundColor = PrompterTheme.dark.background
        } else {
            panel.setFrameAutosaveName("CuePanel")
        }
        #else
        panel.setFrameAutosaveName("CuePanel")
        #endif

        if testHidden {
            // Unattended test runs: the window runs but stays out of the way
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
        }
        panel.contentView = NSHostingView(rootView: ContentView())
        if testHidden { panel.orderFront(nil) } else { panel.makeKeyAndOrderFront(nil) }
        self.panel = panel

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let editorFocused = AppDelegate.isEditorFocused()
            switch event.keyCode {
            case 49:
                if editorFocused { return event }
                AppDelegate.onSpacePressed()
                return nil
            case 53:
                AppDelegate.onEscapePressed()
                return nil
            case 126:
                if editorFocused { return event }
                AppDelegate.onArrowUp()
                return nil
            case 125:
                if editorFocused { return event }
                AppDelegate.onArrowDown()
                return nil
            default:
                return event
            }
        }
        Logger.shared.log("key monitor installed")

        // Cue is a utility — don't let macOS sudden-terminate us when focus bounces.
        ProcessInfo.processInfo.disableSuddenTermination()
    }

    func toggleWindow() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScriptLibrary.shared.flush()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Cue is a menu-bar utility — the status item is the persistent presence.
        false
    }

    #if DEBUG
    /// Window size for README screenshots (a 2x capture is 1280 x 720).
    static let screenshotSize = NSSize(width: 640, height: 360)
    #endif

    /// Centers a window horizontally on the main screen with its top edge
    /// pinned at the very top (so it appears to extend out of the notch area).
    private static func topCenterOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else {
            return NSPoint(x: 200, y: 600)
        }
        let frame = screen.frame
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height
        return NSPoint(x: x, y: y)
    }
}
