import Foundation

final class FileLogger: Sendable {

    static let shared = FileLogger()

    private let directory: URL
    private let maxRuns: Int
    private let currentLogURL: URL

    private init(maxRuns: Int = 5) {
        self.maxRuns = maxRuns
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Detto")
        self.directory = logsDir
        self.currentLogURL = logsDir.appendingPathComponent("detto.log")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        rotateIfNeeded()
        writeRaw("--- Detto launched at \(ISO8601DateFormatter().string(from: Date())) ---\n")
    }

    func log(_ message: String, category: String = "general") {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(category)] \(message)\n"
        writeRaw(line)
    }

    private func writeRaw(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: currentLogURL.path) {
            if let handle = try? FileHandle(forWritingTo: currentLogURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: currentLogURL)
        }
    }

    private func rotateIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: currentLogURL.path) else { return }

        for i in stride(from: maxRuns - 1, through: 1, by: -1) {
            let older = directory.appendingPathComponent("detto.\(i).log")
            let newer = directory.appendingPathComponent("detto.\(i - 1).log")
            if fm.fileExists(atPath: older.path) {
                try? fm.removeItem(at: older)
            }
            if fm.fileExists(atPath: newer.path) {
                try? fm.moveItem(at: newer, to: older)
            }
        }

        let dest = directory.appendingPathComponent("detto.0.log")
        if fm.fileExists(atPath: dest.path) {
            try? fm.removeItem(at: dest)
        }
        try? fm.moveItem(at: currentLogURL, to: dest)
    }
}
