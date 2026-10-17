import XCTest

final class ScriptLibraryTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptLibraryTests-\(UUID().uuidString)")
            .appendingPathComponent("scripts.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    private func makeLibrary() -> ScriptLibrary {
        ScriptLibrary(fileURL: fileURL, practiceText: "Practice makes perfect, read this aloud.")
    }

    private let talk = "Welcome to the quarterly review. Revenue grew in every region."
    private let demo = "Today I'll show you how the export works, step by step."

    func testFirstLaunchShowsThePracticeScriptAndSavesNothing() {
        let library = makeLibrary()
        XCTAssertTrue(library.isPractice)
        XCTAssertEqual(library.text, "Practice makes perfect, read this aloud.")
        library.flush()
        XCTAssertTrue(makeLibrary().recent.isEmpty)
    }

    func testLastScriptIsRestoredOnLaunch() {
        let library = makeLibrary()
        library.edit(talk)
        library.edit(talk + " Costs fell.")
        library.flush()

        let relaunched = makeLibrary()
        XCTAssertFalse(relaunched.isPractice)
        XCTAssertEqual(relaunched.text, talk + " Costs fell.")
        XCTAssertEqual(relaunched.recent.count, 1, "typing edits the same script")
    }

    func testPastingOverEverythingKeepsThePreviousScript() {
        let library = makeLibrary()
        library.edit(talk)
        library.edit(demo)
        XCTAssertEqual(library.text, demo)
        XCTAssertEqual(library.others.map(\.text), [talk])
    }

    func testClearingAScriptStartsANewOneAndEmptyScriptsAreDropped() {
        let library = makeLibrary()
        library.edit(talk)
        library.edit("")
        XCTAssertEqual(library.recent.count, 2)
        library.open(library.others[0].id)
        XCTAssertEqual(library.text, talk)
        XCTAssertEqual(library.recent.count, 1, "the empty script left the list")
    }

    func testOpeningARecentScriptMovesItToTheTop() {
        let library = makeLibrary()
        library.edit(talk)
        library.edit(demo)
        library.open(library.others[0].id)
        XCTAssertEqual(library.text, talk)
        XCTAssertEqual(library.recent.map(\.text), [talk, demo])
        library.flush()
        XCTAssertEqual(makeLibrary().text, talk)
    }

    func testKeepsOnlyTheFiveMostRecent() {
        let library = makeLibrary()
        for n in 1...7 {
            library.newScript()
            library.edit("Script number \(n), with enough words to count.")
        }
        XCTAssertEqual(library.recent.count, 5)
        XCTAssertEqual(library.recent.first?.title, "Script number 7, with enough words to co…")
        XCTAssertEqual(library.recent.last?.text, "Script number 3, with enough words to count.")
    }

    func testPracticeScriptCanBeReopenedAndIsRememberedAsCurrent() {
        let library = makeLibrary()
        library.edit(talk)
        library.openPractice()
        XCTAssertTrue(library.isPractice)
        XCTAssertEqual(library.others.map(\.text), [talk])
        library.flush()

        let relaunched = makeLibrary()
        XCTAssertTrue(relaunched.isPractice)
        XCTAssertEqual(relaunched.others.map(\.text), [talk])
    }

    func testUnreadableFileFallsBackToThePracticeScript() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)
        let library = makeLibrary()
        XCTAssertTrue(library.isPractice)
        XCTAssertTrue(library.recent.isEmpty)
    }

    func testReplacementNeedsMostOfTheTextGone() {
        XCTAssertTrue(ScriptLibrary.isReplacement(old: talk, new: demo))
        XCTAssertTrue(ScriptLibrary.isReplacement(old: talk, new: ""))
        XCTAssertFalse(ScriptLibrary.isReplacement(old: talk, new: talk + " More."))
        XCTAssertFalse(ScriptLibrary.isReplacement(old: talk, new: "Welcome to the review. Revenue grew in every region."))
        XCTAssertFalse(ScriptLibrary.isReplacement(old: "Hi", new: "Hello there"), "short drafts are just edited")
    }

    func testTitleIsTheFirstNonEmptyLine() {
        let script = SavedScript(id: UUID(), text: "\n\n  Intro for the launch video  \nSecond line", updatedAt: Date())
        XCTAssertEqual(script.title, "Intro for the launch video")
    }
}
