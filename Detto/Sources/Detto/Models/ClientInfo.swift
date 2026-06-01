import Foundation

struct ClientInfo: Identifiable, Hashable, Sendable {
    let id: String              // filename without .md
    let name: String            // from H1 heading (fallback: filename)
    let keyContacts: [String]   // from contacts section
    let urgentItem: String?     // from priority section
    let upcomingDates: [String] // from timeline section
    let teamMembers: [String]   // from team section (e.g. "## Crestview Team")

    /// Short label for YAML frontmatter and filenames
    var contextLabel: String { "Client: \(name)" }

    /// Single-line context for YAML frontmatter (kept for backward compat)
    var contextString: String {
        var s = "Client: \(name)"
        if !keyContacts.isEmpty { s += " | Key Contacts: \(keyContacts.joined(separator: ", "))" }
        return s
    }

    /// Structured markdown for the ## Context body in notes
    var formattedContextBody: String {
        var sections: [String] = ["**Client:** \(name)"]

        if !keyContacts.isEmpty {
            let cleaned = keyContacts.map { Self.cleanMarkdown($0) }
            sections.append("### Key Contacts\n" + cleaned.map { "- \($0)" }.joined(separator: "\n"))
        }
        if let item = urgentItem {
            sections.append("### Priority\n- \(Self.cleanMarkdown(item))")
        }
        if !upcomingDates.isEmpty {
            let cleaned = upcomingDates.map { Self.cleanMarkdown($0) }
            sections.append("### Upcoming\n" + cleaned.map { "- \($0)" }.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    var allParticipantNames: [String] {
        (teamMembers + keyContacts).compactMap { Self.extractName($0) }
    }

    static func extractName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("### ") || trimmed.hasPrefix("- **") || trimmed.hasPrefix("**") else { return nil }
        guard let dashRange = trimmed.range(of: " \u{2014} ") else { return nil }
        var name = String(trimmed[trimmed.startIndex..<dashRange.lowerBound])
        name = name.replacingOccurrences(of: "### ", with: "")
            .replacingOccurrences(of: "- ", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
            .trimmingCharacters(in: .whitespaces)
        return name.count >= 2 ? name : nil
    }

    /// Strip markdown formatting for clean display
    static func cleanMarkdown(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
