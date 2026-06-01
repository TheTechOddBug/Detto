import Foundation

struct VocabularyLoader {
    struct VocabularySet: Sendable {
        let terms: [String]
        let corrections: [String: String]
    }

    static func load(from directory: URL) -> VocabularySet {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return VocabularySet(terms: [], corrections: [:])
        }

        var terms: [String] = []
        var corrections: [String: String] = [:]

        let txtFiles = files
            .filter { $0.pathExtension.lowercased() == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for file in txtFiles {
            guard var content = try? String(contentsOf: file, encoding: .utf8) else { continue }

            // Strip UTF-8 BOM
            if content.hasPrefix("\u{FEFF}") {
                content = String(content.dropFirst())
            }

            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

                if let eqRange = trimmed.range(of: " = ") {
                    let key = String(trimmed[trimmed.startIndex..<eqRange.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                    let value = String(trimmed[eqRange.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                    if !key.isEmpty && !value.isEmpty {
                        corrections[key] = value
                    }
                } else {
                    terms.append(trimmed)
                }
            }
        }

        let uniqueTerms = Array(Set(terms))
        return VocabularySet(terms: uniqueTerms, corrections: corrections)
    }
}
