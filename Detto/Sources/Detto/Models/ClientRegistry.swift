import Foundation
import Observation
import os

@Observable
@MainActor
final class ClientRegistry {
    private let log = Logger(subsystem: "io.gremble.detto", category: "ClientRegistry")

    private(set) var allClients: [ClientInfo] = []
    var selectedClient: ClientInfo?
    var scanError: String?

    var hasClients: Bool { !allClients.isEmpty }

    /// Top clients by usage frequency.
    func topClients(count: Int = 9) -> [ClientInfo] {
        let counts = UserDefaults.standard.dictionary(forKey: "clientUsageCounts") as? [String: Int] ?? [:]
        return Array(allClients.sorted {
            let c0 = counts[$0.id] ?? 0
            let c1 = counts[$1.id] ?? 0
            if c0 != c1 { return c0 > c1 }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }.prefix(count))
    }

    /// Clients not in the top N.
    func remainingClients(afterTop count: Int = 9) -> [ClientInfo] {
        let top = Set(topClients(count: count).map(\.id))
        return allClients.filter { !top.contains($0.id) }
    }

    /// Record that a client was used for a session.
    func recordUsage(for client: ClientInfo) {
        var counts = UserDefaults.standard.dictionary(forKey: "clientUsageCounts") as? [String: Int] ?? [:]
        counts[client.id] = (counts[client.id] ?? 0) + 1
        UserDefaults.standard.set(counts, forKey: "clientUsageCounts")
    }

    /// Scan the vault for client files. All I/O runs off the main thread.
    func scan(vaultRoot: URL) async {
        scanError = nil
        let results = await Task.detached { [log] in
            return Self.parseClients(vaultRoot: vaultRoot, log: log)
        }.value

        switch results {
        case .success(let clients):
            allClients = clients
            if clients.isEmpty {
                scanError = "No client files found. Expected .md files with type: client frontmatter in the clients folder."
            }
        case .failure(let error):
            allClients = []
            scanError = error.text
        }
    }

    // MARK: - Parsing (runs off main thread)

    private enum ScanError: Error {
        case message(String)
        var text: String {
            switch self { case .message(let s): return s }
        }
    }

    private nonisolated static func parseClients(vaultRoot: URL, log: Logger) -> Result<[ClientInfo], ScanError> {
        let config = DettoVaultConfig.load(from: vaultRoot)
        let clientsDir = vaultRoot.appendingPathComponent(config.clientsPath)

        guard FileManager.default.fileExists(atPath: clientsDir.path) else {
            return .failure(.message("Clients folder not found at \(config.clientsPath)/. Check your vault root or .detto.yaml config."))
        }

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: clientsDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            )
        } catch {
            return .failure(.message("Could not read \(config.clientsPath)/: \(error.localizedDescription)"))
        }

        let mdFiles = contents
            .filter { $0.pathExtension == "md" }
            .filter { !$0.lastPathComponent.hasSuffix(".icloud") }
            .filter { !$0.lastPathComponent.contains("conflicted") }
            .filter { !$0.lastPathComponent.contains(".sync-conflict-") }
            .prefix(1000)

        var clients: [ClientInfo] = []

        for fileURL in mdFiles {
            guard var content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            // Normalize line endings and strip BOM
            if content.hasPrefix("\u{FEFF}") { content = String(content.dropFirst()) }
            content = content.replacingOccurrences(of: "\r\n", with: "\n")
                             .replacingOccurrences(of: "\r", with: "\n")

            let lines = content.components(separatedBy: "\n")

            // Extract frontmatter (between first two --- delimiters)
            guard let frontmatter = extractFrontmatter(lines: lines) else { continue }

            // Match client type in frontmatter only
            let typePattern = "type\\s*:\\s*[\"']?\(NSRegularExpression.escapedPattern(for: config.clientType))[\"']?\\s*(#.*)?"
            guard let typeRegex = try? NSRegularExpression(pattern: typePattern, options: .caseInsensitive),
                  typeRegex.firstMatch(in: frontmatter, range: NSRange(frontmatter.startIndex..., in: frontmatter)) != nil else {
                continue
            }

            // Extract client name from first H1 heading after frontmatter
            let filename = fileURL.deletingPathExtension().lastPathComponent
            let name = extractH1(lines: lines) ?? filename

            let keyContacts = extractSection(lines: lines, matchingAny: config.contactsHeadings)
            let urgentItem = extractSection(lines: lines, matchingAny: config.priorityHeadings).first
            let upcomingDates = Array(extractSection(lines: lines, matchingAny: config.timelineHeadings).prefix(3))
            let teamMembers = extractSection(lines: lines, matchingAny: config.teamHeadings)

            clients.append(ClientInfo(
                id: filename,
                name: name,
                keyContacts: keyContacts,
                urgentItem: urgentItem,
                upcomingDates: upcomingDates,
                teamMembers: teamMembers
            ))
        }

        return .success(clients.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    /// Extract the text between the first two `---` delimiters.
    private nonisolated static func extractFrontmatter(lines: [String]) -> String? {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        var fmLines: [String] = []
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                return fmLines.joined(separator: "\n")
            }
            fmLines.append(line)
        }
        return nil
    }

    /// Extract the first H1 heading after frontmatter, stripping markdown formatting.
    private nonisolated static func extractH1(lines: [String]) -> String? {
        var pastFrontmatter = false
        var sawFirstDelimiter = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                if !sawFirstDelimiter {
                    sawFirstDelimiter = true
                } else {
                    pastFrontmatter = true
                }
                continue
            }
            if pastFrontmatter && trimmed.hasPrefix("# ") {
                var name = String(trimmed.dropFirst(2))
                // Strip markdown: bold, italic, links
                name = name.replacingOccurrences(of: "**", with: "")
                name = name.replacingOccurrences(of: "*", with: "")
                name = name.replacingOccurrences(of: "_", with: "")
                // Strip link syntax: [text](url) → text
                if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\([^)]+\\)") {
                    name = regex.stringByReplacingMatches(in: name, range: NSRange(name.startIndex..., in: name), withTemplate: "$1")
                }
                let result = name.trimmingCharacters(in: .whitespaces)
                return result.isEmpty ? nil : result
            }
        }
        return nil
    }

    /// Extract lines from the first section whose H2 heading contains any of the given keywords (case-insensitive).
    private nonisolated static func extractSection(lines: [String], matchingAny keywords: [String]) -> [String] {
        for keyword in keywords {
            let result = extractSection(lines: lines, containing: keyword)
            if !result.isEmpty { return result }
        }
        return []
    }

    private nonisolated static func extractSection(lines: [String], containing keyword: String) -> [String] {
        let lowerKeyword = keyword.lowercased()
        var capturing = false
        var result: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                if capturing { break }  // hit next section
                let heading = String(trimmed.dropFirst(3))
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                    .lowercased()
                if heading.contains(lowerKeyword) {
                    capturing = true
                }
                continue
            }

            if trimmed.hasPrefix("# ") || trimmed == "---" {
                if capturing { break }
                continue
            }

            if capturing && !trimmed.isEmpty {
                // Strip list markers (-, *, numbered)
                var cleaned = trimmed
                if cleaned.hasPrefix("- ") { cleaned = String(cleaned.dropFirst(2)) }
                else if cleaned.hasPrefix("* ") { cleaned = String(cleaned.dropFirst(2)) }
                else if let dotRange = cleaned.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                    cleaned = String(cleaned[dotRange.upperBound...])
                }
                result.append(cleaned.trimmingCharacters(in: .whitespaces))
            }
        }

        return result
    }
}
