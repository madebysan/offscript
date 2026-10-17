import AppKit
import SwiftUI

@main
struct CueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Offscript") {
                    Self.showAboutPanel()
                }
                Button("Check for Updates…") {
                    Updates.check()
                }
            }
        }
    }

    static func showAboutPanel() {
        let url = URL(string: "https://santiagoalonso.com")!
        let credits = NSMutableAttributedString(
            string: "Made by santiagoalonso.com",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor,
                .link: url,
                .cursor: NSCursor.pointingHand
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "Offscript",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MenuBarContent: View {
    @ObservedObject private var permissions = Permissions.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Show/Hide Window") {
            AppDelegate.shared?.toggleWindow()
        }
        .keyboardShortcut("h")

        Divider()

        permissionButton(.microphone)
        permissionButton(.speech)

        if permissions.microphone == .notDetermined || permissions.speech == .notDetermined {
            Button("Allow Microphone and Speech Recognition…") {
                permissions.request(fromMenu: true)
            }
        }

        Divider()

        // Without a Dock icon the app must come forward, or Settings opens behind other windows
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")

        Button("About Offscript") {
            CueApp.showAboutPanel()
        }

        Button("Check for Updates…") {
            Updates.check()
        }

        Divider()

        Button("Quit Offscript") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// Shows the status; asks when undecided, otherwise opens the System Settings pane.
    private func permissionButton(_ kind: Permissions.Kind) -> some View {
        let state = permissions.state(of: kind)
        return Button("\(kind.name): \(label(for: state))") {
            if state == .notDetermined {
                permissions.request(fromMenu: true)
            } else {
                permissions.openSettings(for: kind)
            }
        }
    }

    private func label(for state: Permissions.State) -> String {
        switch state {
        case .granted: return "Allowed"
        case .denied: return "Off, open Settings"
        case .restricted: return "Blocked by your Mac's settings"
        case .notDetermined: return "Not asked yet"
        }
    }
}
