import Foundation
import os

/// Configuration for how Detto reads client data from an Obsidian vault.
/// Loaded from an optional `.detto.yaml` in the vault root; all fields have sensible defaults.
struct DettoVaultConfig: Sendable {
    let clientsPath: String
    let clientType: String
    let contactsHeadings: [String]
    let priorityHeadings: [String]
    let timelineHeadings: [String]
    let teamHeadings: [String]

    static let `default` = DettoVaultConfig(
        clientsPath: "Clients",
        clientType: "client",
        contactsHeadings: ["Contact"],
        priorityHeadings: ["Priority", "Mandate"],
        timelineHeadings: ["Timeline", "Upcoming", "Track"],
        teamHeadings: ["Team", "Crestview"]
    )

    /// Load config from `.detto.yaml` in vault root, merging with defaults.
    /// Missing fields fall back to defaults. If no config file exists, returns `.default`.
    static func load(from vaultRoot: URL) -> DettoVaultConfig {
        let configURL = vaultRoot.appendingPathComponent(".detto.yaml")
        guard let data = try? String(contentsOf: configURL, encoding: .utf8) else {
            return .default
        }

        let lines = data.replacingOccurrences(of: "\r\n", with: "\n")
                        .replacingOccurrences(of: "\r", with: "\n")
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .map(String.init)

        var clientsPath = DettoVaultConfig.default.clientsPath
        var clientType = DettoVaultConfig.default.clientType
        var contactsHeadings = DettoVaultConfig.default.contactsHeadings
        var priorityHeadings = DettoVaultConfig.default.priorityHeadings
        var timelineHeadings = DettoVaultConfig.default.timelineHeadings
        var teamHeadings = DettoVaultConfig.default.teamHeadings

        var inSections = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("clientsPath:") {
                clientsPath = extractValue(trimmed) ?? clientsPath
                inSections = false
            } else if trimmed.hasPrefix("clientType:") {
                clientType = extractValue(trimmed) ?? clientType
                inSections = false
            } else if trimmed == "sections:" {
                inSections = true
            } else if inSections {
                if trimmed.hasPrefix("contacts:") {
                    contactsHeadings = extractList(trimmed) ?? contactsHeadings
                } else if trimmed.hasPrefix("priority:") {
                    priorityHeadings = extractList(trimmed) ?? priorityHeadings
                } else if trimmed.hasPrefix("timeline:") {
                    timelineHeadings = extractList(trimmed) ?? timelineHeadings
                } else if trimmed.hasPrefix("team:") {
                    teamHeadings = extractList(trimmed) ?? teamHeadings
                } else if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    inSections = false
                }
            }
        }

        return DettoVaultConfig(
            clientsPath: clientsPath,
            clientType: clientType,
            contactsHeadings: contactsHeadings,
            priorityHeadings: priorityHeadings,
            timelineHeadings: timelineHeadings,
            teamHeadings: teamHeadings
        )
    }

    /// Extract a comma-separated list of values after the first colon.
    private static func extractList(_ line: String) -> [String]? {
        guard let raw = extractValue(line) else { return nil }
        let items = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return items.isEmpty ? nil : items
    }

    /// Extract the value after the first colon, trimming whitespace and quotes.
    private static func extractValue(_ line: String) -> String? {
        guard let colonIdx = line.firstIndex(of: ":") else { return nil }
        var value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
        // Strip surrounding quotes
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
           (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return value.isEmpty ? nil : value
    }
}
