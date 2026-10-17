import AppKit
import XCTest

/// README screenshot. `scripts/store-screenshots/generate.sh` runs this and exports the named attachment.
/// The attachment name must match the `capture` key in `scripts/store-screenshots/slots.json`.
///
/// Offscript's prompter is a borderless floating panel that UI tests can't see through
/// accessibility, so the test finds the panel's bounds in the window list and crops the
/// screen capture to it. Only the panel's own area is kept.
final class StoreScreenshots: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { XCUIApplication().terminate() }

    @MainActor
    func testCaptureStoreSet() throws {
        let app = XCUIApplication()
        // Debug-only screenshot mode: the practice script in a throwaway library, mid-read,
        // no microphone. The settings come from launch arguments, which macOS doesn't save.
        app.launchArguments = [
            "--screenshots",
            "-theme", "dark",
            "-backgroundOpacity", "1",
            "-defaultTextSize", "22",
            "-fontFamily", "System",
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        Thread.sleep(forTimeInterval: 2)

        let bounds = try XCTUnwrap(prompterBounds(), "The prompter window should be on screen")
        XCTAssertEqual(bounds.width, 640, accuracy: 1, "Screenshot mode sets a 640 x 360 window")
        XCTAssertEqual(bounds.height, 360, accuracy: 1, "Screenshot mode sets a 640 x 360 window")

        let screen = XCUIScreen.main.screenshot().image
        let image = try XCTUnwrap(crop(screen, to: bounds), "Couldn't crop the screen capture")
        let shot = XCTAttachment(image: image)
        shot.name = "prompter"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The largest on-screen window owned by Offscript, in global top-left coordinates.
    private func prompterBounds() -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return list
            .filter { ($0[kCGWindowOwnerName as String] as? String) == "Offscript" }
            .compactMap { info -> CGRect? in
                guard let dict = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
                return CGRect(dictionaryRepresentation: dict)
            }
            .filter { $0.width > 100 && $0.height > 60 }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    /// Crops a main-screen capture to a rect in points.
    private func crop(_ image: NSImage, to rect: CGRect) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let screen = NSScreen.screens.first else { return nil }
        let scale = CGFloat(cg.width) / screen.frame.width
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
        guard let cropped = cg.cropping(to: pixels) else { return nil }
        return NSImage(cgImage: cropped, size: rect.size)
    }
}
