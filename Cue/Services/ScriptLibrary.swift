import Foundation

/// A script the user wrote or pasted, kept between launches.
struct SavedScript: Codable, Equatable, Identifiable {
    var id: UUID
    var text: String
    var updatedAt: Date

    /// The first non-empty line, shortened for menus.
    var title: String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "Untitled"
        return line.count > 40 ? String(line.prefix(40)).trimmingCharacters(in: .whitespaces) + "…" : line
    }
}

/// Remembers the script on screen and the last few scripts used, in one JSON file
/// in Application Support. The current script is always first in `recent`;
/// `currentID == nil` means the built-in practice script, which is never saved.
final class ScriptLibrary: ObservableObject {
    static let shared: ScriptLibrary = {
        #if DEBUG
        // Test runs use a throwaway file so they never touch your recent scripts
        if CommandLine.arguments.contains("--test-script") {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-scripts.json")
            try? FileManager.default.removeItem(at: url)
            return ScriptLibrary(fileURL: url)
        }
        #endif
        return ScriptLibrary(fileURL: defaultFileURL)
    }()

    @Published private(set) var text: String
    @Published private(set) var recent: [SavedScript] = []
    private(set) var currentID: UUID?

    let limit: Int
    private let fileURL: URL
    private let practiceText: String
    private let saveDelay: TimeInterval
    private var pendingSave: DispatchWorkItem?

    private struct Stored: Codable {
        var version = 1
        var currentID: UUID?
        var scripts: [SavedScript]
    }

    static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Offscript", isDirectory: true)
            .appendingPathComponent("scripts.json")
    }

    init(fileURL: URL, limit: Int = 5, practiceText: String = PracticeScript.text, saveDelay: TimeInterval = 0.5) {
        self.fileURL = fileURL
        self.limit = limit
        self.practiceText = practiceText
        self.saveDelay = saveDelay
        self.text = practiceText

        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            Logger.shared.log("ScriptLibrary: couldn't read \(fileURL.lastPathComponent); starting with the practice script")
            return
        }
        recent = Array(stored.scripts.prefix(limit))
        if let id = stored.currentID, let current = recent.first(where: { $0.id == id }) {
            currentID = id
            text = current.text
            moveToFront(id)
        }
        Logger.shared.log("ScriptLibrary: restored \(recent.count) scripts, current=\(currentID == nil ? "practice" : "saved")")
    }

    var isPractice: Bool { currentID == nil }

    /// Recent scripts other than the one on screen, for the menu.
    var others: [SavedScript] {
        recent.filter { $0.id != currentID && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Called on every edit. Replacing most of the text (select all and paste)
    /// starts a new script, so the one it replaced stays in the recent list.
    func edit(_ newText: String) {
        guard newText != text else { return }
        let old = text
        text = newText
        if currentID == nil || Self.isReplacement(old: old, new: newText) {
            if newText == practiceText { return }
            insertNew(newText)
        } else if let i = recent.firstIndex(where: { $0.id == currentID }) {
            recent[i].text = newText
            recent[i].updatedAt = Date()
        }
        // Pasting or undoing back to a script already in the list keeps one copy
        recent.removeAll { $0.id != currentID && $0.text == newText }
        scheduleSave()
    }

    /// Starts an empty script; the current one stays in the recent list.
    func newScript() {
        if !isPractice, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        text = ""
        insertNew("")
        scheduleSave()
    }

    func open(_ id: UUID) {
        guard id != currentID, let script = recent.first(where: { $0.id == id }) else { return }
        dropEmptyCurrent()
        currentID = id
        text = script.text
        moveToFront(id)
        scheduleSave()
    }

    func openPractice() {
        guard !isPractice else { return }
        dropEmptyCurrent()
        currentID = nil
        text = practiceText
        scheduleSave()
    }

    /// Writes unsaved changes now, for quitting and tests. With nothing unsaved it
    /// writes nothing, so it can't overwrite a newer file from another copy of the app.
    func flush() {
        guard let pending = pendingSave else { return }
        pending.cancel()
        pendingSave = nil
        save()
    }

    /// True when an edit kept less than a fifth of a longer script: a paste over
    /// everything, or clearing it. Small drafts are just edited.
    static func isReplacement(old: String, new: String) -> Bool {
        let oldChars = Array(old), newChars = Array(new)
        guard old.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 else { return false }
        var prefix = 0
        while prefix < oldChars.count, prefix < newChars.count, oldChars[prefix] == newChars[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < oldChars.count - prefix, suffix < newChars.count - prefix,
              oldChars[oldChars.count - 1 - suffix] == newChars[newChars.count - 1 - suffix] { suffix += 1 }
        return Double(prefix + suffix) < Double(oldChars.count) * 0.2
    }

    // MARK: - Private

    private func insertNew(_ newText: String) {
        dropEmptyCurrent()
        let script = SavedScript(id: UUID(), text: newText, updatedAt: Date())
        recent.insert(script, at: 0)
        if recent.count > limit { recent.removeLast(recent.count - limit) }
        currentID = script.id
    }

    /// An empty script isn't worth a place in the list once you move away from it.
    private func dropEmptyCurrent() {
        guard let id = currentID,
              let script = recent.first(where: { $0.id == id }),
              script.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        recent.removeAll { $0.id == id }
    }

    private func moveToFront(_ id: UUID) {
        guard let i = recent.firstIndex(where: { $0.id == id }), i > 0 else { return }
        recent.insert(recent.remove(at: i), at: 0)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: work)
    }

    private func save() {
        let stored = Stored(currentID: currentID, scripts: recent)
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(stored)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Logger.shared.log("ScriptLibrary: save failed: \(error.localizedDescription)")
        }
    }
}
