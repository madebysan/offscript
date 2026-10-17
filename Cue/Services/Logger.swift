import Foundation

/// File logger. Writes in every config during the v0 debug phase so we can tail it.
/// Path (sandboxed app): ~/Library/Containers/com.san.Cue/Data/Library/Logs/Cue/app.log
final class Logger {
    static let shared = Logger()

    private let fileURL: URL?
    private let queue = DispatchQueue(label: "com.san.Cue.logger", qos: .utility)
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let logsDir = home.appendingPathComponent("Library/Logs/Cue", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.fileURL = logsDir.appendingPathComponent("app.log")
        if let url = fileURL {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
        log("=== Cue launched ===")
        if let url = fileURL { log("log path: \(url.path)") }
    }

    func log(_ message: String) {
        let timestamp = iso.string(from: Date())
        let line = "\(timestamp)  \(message)\n"
        guard let fileURL else { return }
        queue.async {
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    try? line.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            }
        }
        print(line, terminator: "")
    }
}
