import AppKit
import Sparkle

// In-app updates. The feed lives on the repo's GitHub Releases (Info.plist
// SUFeedURL). Started only from a bundle that has a feed URL.
enum Updates {
    static let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
    )

    static func start() {
        if Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil {
            controller.startUpdater()
        }
    }

    static func check() {
        // No Dock icon, so bring the app forward or the update window opens behind others
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
