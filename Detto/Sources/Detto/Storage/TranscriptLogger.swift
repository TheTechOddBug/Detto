import Foundation

enum TranscriptLoggerError: LocalizedError {
    case cannotCreateFile(String)
    var errorDescription: String? {
        switch self { case .cannotCreateFile(let p): return "Cannot create transcript at \(p)" }
    }
}

/// Writes structured markdown transcripts to the vault.
actor TranscriptLogger {
    private static func yamlScalar(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }

    private static func yamlStringArray(_ values: [String]) -> String {
        values.isEmpty ? "[]" : "[" + values.map(yamlScalar).joined(separator: ", ") + "]"
    }

    private var fileHandle: FileHandle?
    private var currentFilePath: URL?
    private var sessionStartTime: Date?
    private var speakersDetected: Set<String> = []
    private var sourceApp: String = "manual"
    private var sessionContext: String = ""
    private var utteranceBuffer: [(speaker: String, text: String, timestamp: Date)] = []

    // Retained from last session for frontmatter finalization
    private var lastSessionFilePath: URL?
    private var lastSessionStartTime: Date?
    private var lastSpeakersDetected: Set<String> = []
    private var lastSessionContext: String = ""

    func startSession(sourceApp: String, vaultPath: String, sessionType: SessionType = .callCapture, context: String? = nil, contextBody: String? = nil, client: ClientInfo? = nil, attendees: String? = nil) throws {
        self.sourceApp = sourceApp
        self.sessionStartTime = Date()
        self.speakersDetected = []
        self.sessionContext = client?.contextLabel ?? context ?? ""
        self.utteranceBuffer = []

        let expandedPath = NSString(string: vaultPath).expandingTildeInPath
        let directory = URL(fileURLWithPath: expandedPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let now = sessionStartTime!
        let fileFmt = DateFormatter()
        fileFmt.dateFormat = "yyyy-MM-dd HH-mm-ss"

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"

        let dateStr = dateFmt.string(from: now)
        let timeStr = timeFmt.string(from: now)

        let isVoiceMemo = sessionType == .voiceMemo
        let fileLabel = isVoiceMemo ? "Voice Memo" : "Call Recording"
        let noteType = isVoiceMemo ? "fleeting" : "meeting"
        let logTag = isVoiceMemo ? "log/voice" : "log/meeting"
        let sourceTag = isVoiceMemo ? "source/voice" : "source/meeting"

        let filename = "\(fileFmt.string(from: now)) \(fileLabel).md"
        currentFilePath = directory.appendingPathComponent(filename)

        let shortContext = sessionContext.trimmingCharacters(in: .whitespacesAndNewlines)

        let attendeeNames: [String]
        if let attendees, !attendees.isEmpty {
            attendeeNames = attendees.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } else {
            attendeeNames = []
        }
        let attendeesYaml = Self.yamlStringArray(attendeeNames)

        // Structured body for ## Context section
        var resolvedContextBody: String
        if let client {
            resolvedContextBody = client.formattedContextBody
        } else if let contextBody, !contextBody.isEmpty {
            resolvedContextBody = contextBody
        } else if !sessionContext.isEmpty {
            resolvedContextBody = sessionContext
        } else {
            resolvedContextBody = ""
        }
        if !attendeeNames.isEmpty {
            let attendeesLine = "**Attendees:** \(attendeeNames.joined(separator: ", "))"
            if resolvedContextBody.isEmpty {
                resolvedContextBody = attendeesLine
            } else {
                resolvedContextBody = attendeesLine + "\n\n" + resolvedContextBody
            }
        }

        let dettoVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        let content = """
---
type: \(noteType)
created: "\(dateStr)"
time: "\(timeStr)"
duration: "00:00"
detto_version: "\(dettoVersion)"
source_app: \(Self.yamlScalar(sourceApp))
source_file: \(Self.yamlScalar(filename))
attendees: \(attendeesYaml)
context: \(Self.yamlScalar(shortContext))
tags:
  - \(logTag)
  - status/inbox
  - \(sourceTag)
  - source/detto
---

# \(fileLabel) — \(dateStr) \(timeStr)

**Duration:** 00:00 | **Speakers:** 0

---

## Context

\(resolvedContextBody)

---

## Transcript

"""

        let created = FileManager.default.createFile(atPath: currentFilePath!.path, contents: content.data(using: .utf8))
        guard created else { throw TranscriptLoggerError.cannotCreateFile(currentFilePath!.path) }
        fileHandle = try FileHandle(forWritingTo: currentFilePath!)
        fileHandle?.seekToEndOfFile()
    }

    func append(speaker: String, text: String, timestamp: Date) {
        speakersDetected.insert(speaker)
        utteranceBuffer.append((speaker: speaker, text: text, timestamp: timestamp))
        flushBuffer()
    }

    /// Periodic flush — call from a timer or at intervals
    func flushIfNeeded() {
        if !utteranceBuffer.isEmpty {
            flushBuffer()
        }
    }

    private func flushBuffer() {
        guard let fileHandle, !utteranceBuffer.isEmpty else { return }

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm:ss"

        var lines = ""
        for entry in utteranceBuffer {
            lines += "**\(entry.speaker)** (\(timeFmt.string(from: entry.timestamp)))\n"
            lines += "\(entry.text)\n\n"
        }

        if let data = lines.data(using: .utf8) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
        }

        utteranceBuffer.removeAll()
    }

    func updateContext(_ text: String) {
        guard let filePath = currentFilePath else { return }

        // Flush any buffered utterances first
        flushBuffer()
        try? fileHandle?.close()
        fileHandle = nil

        guard var content = try? String(contentsOf: filePath, encoding: .utf8) else { return }

        // Only update the ### Notes subsection — preserve structured context
        let dividerMarker = "\n---\n\n## Transcript"
        if let notesStart = content.range(of: "### Notes\n") {
            // Replace existing notes content up to the divider
            if let end = content.range(of: dividerMarker, range: notesStart.upperBound..<content.endIndex) {
                content.replaceSubrange(notesStart.upperBound..<end.lowerBound, with: text + "\n")
            }
        } else if let contextEnd = content.range(of: dividerMarker) {
            // No ### Notes yet — insert before the divider
            content.insert(contentsOf: "\n### Notes\n\(text)\n", at: contextEnd.lowerBound)
        }

        let tmpPath = filePath.deletingLastPathComponent().appendingPathComponent(".detto_tmp.md")
        do {
            try content.write(to: tmpPath, atomically: true, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(filePath, withItemAt: tmpPath)
        } catch {
            try? FileManager.default.removeItem(at: tmpPath)
        }

        // Reopen file handle
        fileHandle = try? FileHandle(forWritingTo: filePath)
        fileHandle?.seekToEndOfFile()
    }

    func updateAttendees(_ text: String) {
        let names = text.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        flushBuffer()
        try? fileHandle?.close()
        fileHandle = nil

        guard let filePath = currentFilePath,
              var content = try? String(contentsOf: filePath, encoding: .utf8) else {
            if let fp = currentFilePath {
                fileHandle = try? FileHandle(forWritingTo: fp)
                fileHandle?.seekToEndOfFile()
            }
            return
        }

        let attendeesYaml = Self.yamlStringArray(names)
        if let range = content.range(of: #"attendees: \[.*\]"#, options: .regularExpression) {
            content.replaceSubrange(range, with: "attendees: \(attendeesYaml)")
        }

        let attendeesLine = "**Attendees:** \(text)"
        if let range = content.range(of: #"\*\*Attendees:\*\* .*"#, options: .regularExpression) {
            content.replaceSubrange(range, with: attendeesLine)
        } else if let contextStart = content.range(of: "## Context\n") {
            content.insert(contentsOf: "\n\(attendeesLine)\n", at: contextStart.upperBound)
        }

        let tmpPath = filePath.deletingLastPathComponent().appendingPathComponent(".detto_tmp.md")
        do {
            try content.write(to: tmpPath, atomically: true, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(filePath, withItemAt: tmpPath)
        } catch {
            try? FileManager.default.removeItem(at: tmpPath)
        }

        fileHandle = try? FileHandle(forWritingTo: filePath)
        fileHandle?.seekToEndOfFile()
    }

    func updateSpeakers(_ speakers: Set<String>) {
        lastSpeakersDetected = speakers
    }

    func rewriteTranscriptBody(from utterances: [Utterance]) {
        guard let filePath = lastSessionFilePath else { return }
        guard var content = try? String(contentsOf: filePath, encoding: .utf8) else { return }

        let marker = "## Transcript\n"
        guard let transcriptStart = content.range(of: marker) else { return }

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm:ss"

        var body = "\n"
        for utterance in utterances {
            body += "**\(utterance.speakerName)** (\(timeFmt.string(from: utterance.timestamp)))\n"
            body += "\(utterance.text)\n\n"
        }

        content.replaceSubrange(transcriptStart.upperBound..<content.endIndex, with: body)

        let tmpPath = filePath.deletingLastPathComponent().appendingPathComponent(".detto_rewrite_tmp.md")
        do {
            try content.write(to: tmpPath, atomically: true, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(filePath, withItemAt: tmpPath)
        } catch {
            try? FileManager.default.removeItem(at: tmpPath)
        }
    }

    func endSession() {
        // Flush remaining buffer
        flushBuffer()

        // Close file handle immediately so next session can start
        try? fileHandle?.close()
        fileHandle = nil

        // Retain for post-session diarization and frontmatter finalization
        lastSessionFilePath = currentFilePath
        lastSessionStartTime = sessionStartTime
        lastSpeakersDetected = speakersDetected
        lastSessionContext = sessionContext

        // Reset state immediately so next session can start
        currentFilePath = nil
        sessionStartTime = nil
        speakersDetected = []
        sessionContext = ""
    }

    /// Call AFTER diarization is complete. Rewrites frontmatter with correct
    /// duration, speaker count, attendees, and optionally renames the file.
    @discardableResult
    func finalizeFrontmatter() async -> URL? {
        guard let filePath = lastSessionFilePath,
              let startTime = lastSessionStartTime else { return nil }

        await Self.rewriteFrontmatter(
            filePath: filePath,
            startTime: startTime,
            speakers: lastSpeakersDetected,
            context: lastSessionContext
        )

        // Update lastSessionFilePath if the file was renamed
        if !lastSessionContext.isEmpty {
            let truncated = Self.cleanFilenameContext(lastSessionContext)
            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "yyyy-MM-dd HH-mm-ss"
            let datePrefix = dateFmt.string(from: startTime)
            let newFilename = "\(datePrefix) \(truncated).md"
            let newPath = filePath.deletingLastPathComponent().appendingPathComponent(newFilename)
            lastSessionFilePath = newPath
        }

        let savedPath = lastSessionFilePath
        lastSessionStartTime = nil
        lastSpeakersDetected = []
        lastSessionContext = ""
        return savedPath
    }

    private static func rewriteFrontmatter(
        filePath: URL,
        startTime: Date,
        speakers: Set<String>,
        context: String
    ) async {
        guard var content = try? String(contentsOf: filePath, encoding: .utf8) else { return }

        // Calculate duration
        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        let durationStr = String(format: "%02d:%02d", minutes, seconds)

        // Build attendees array
        let sortedSpeakers = speakers.sorted()
        let attendeesYaml = yamlStringArray(sortedSpeakers)

        // Update frontmatter fields (regex to handle already-rewritten values)
        if let range = content.range(of: #"duration: "\d{2}:\d{2}""#, options: .regularExpression) {
            content.replaceSubrange(range, with: "duration: \"\(durationStr)\"")
        }
        if let range = content.range(of: #"attendees: \[.*\]"#, options: .regularExpression) {
            content.replaceSubrange(range, with: "attendees: \(attendeesYaml)")
        }

        // Update header line (regex to handle already-rewritten values)
        if let range = content.range(of: #"\*\*Duration:\*\* \d{2}:\d{2} \| \*\*Speakers:\*\* \d+"#, options: .regularExpression) {
            content.replaceSubrange(range, with: "**Duration:** \(durationStr) | **Speakers:** \(speakers.count)")
        }

        // Context-based file rename
        var finalPath = filePath
        if !context.isEmpty {
            let truncated = cleanFilenameContext(context)

            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "yyyy-MM-dd HH-mm-ss"
            let datePrefix = dateFmt.string(from: startTime)
            let newFilename = "\(datePrefix) \(truncated).md"
            let newPath = filePath.deletingLastPathComponent().appendingPathComponent(newFilename)

            // Update source_file in content
            if let range = content.range(of: #"source_file: ".*""#, options: .regularExpression) {
                content.replaceSubrange(range, with: "source_file: \(yamlScalar(newFilename))")
            }

            finalPath = newPath
        }

        let tmpPath = filePath.deletingLastPathComponent().appendingPathComponent(".detto_tmp.md")
        do {
            try content.write(to: tmpPath, atomically: true, encoding: .utf8)
            if finalPath != filePath {
                try FileManager.default.moveItem(at: tmpPath, to: finalPath)
                try? FileManager.default.removeItem(at: filePath)
            } else {
                _ = try FileManager.default.replaceItemAt(filePath, withItemAt: tmpPath)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmpPath)
        }
    }

    /// Extract clean client name for filenames — strips everything after " | "
    private static func cleanFilenameContext(_ context: String) -> String {
        let base: String
        if let pipeIdx = context.range(of: " | ") {
            base = String(context[context.startIndex..<pipeIdx.lowerBound])
        } else {
            base = String(context.prefix(50))
        }
        return base
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
    }

}
