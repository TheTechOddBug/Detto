import Foundation

struct VocabularyCorrector: Sendable {
    struct Result: Sendable {
        let text: String
        let corrections: [(original: String, corrected: String, rule: String)]
    }

    private let explicitCorrections: [(pattern: String, replacement: String)]
    private let caseLookup: [String: String]
    private let multiWordCaseLookup: [String: String]
    private let singleWordTerms: [String]

    var termCount: Int { caseLookup.count + multiWordCaseLookup.count }
    var correctionCount: Int { explicitCorrections.count }

    init(terms: [String], corrections: [String: String]) {
        // Pass 1 setup: sort corrections longest-first
        self.explicitCorrections = corrections
            .map { (pattern: $0.key, replacement: $0.value) }
            .sorted { $0.pattern.count > $1.pattern.count }

        // Pass 2 setup: case normalization dictionaries
        var caseLookup: [String: String] = [:]
        var multiWordCaseLookup: [String: String] = [:]
        var singleWordTerms: [String] = []

        for term in terms {
            let words = term.split(separator: " ")
            if words.count == 1 {
                caseLookup[term.lowercased()] = term
                singleWordTerms.append(term)
            } else {
                multiWordCaseLookup[term.lowercased()] = term
            }
        }
        // Also add correction targets as case normalization entries
        for value in corrections.values {
            let words = value.split(separator: " ")
            if words.count == 1 {
                caseLookup[value.lowercased()] = value
            } else {
                multiWordCaseLookup[value.lowercased()] = value
            }
        }

        self.caseLookup = caseLookup
        self.multiWordCaseLookup = multiWordCaseLookup
        self.singleWordTerms = singleWordTerms
    }

    func correct(_ text: String) -> Result {
        var current = text
        var corrections: [(original: String, corrected: String, rule: String)] = []

        // Track which character ranges have been corrected (by pass 1)
        var correctedRanges: [Range<String.Index>] = []

        // Pass 1: Explicit corrections
        for entry in explicitCorrections {
            var searchStart = current.startIndex
            while searchStart < current.endIndex {
                guard let range = current.range(
                    of: entry.pattern,
                    options: .caseInsensitive,
                    range: searchStart..<current.endIndex
                ) else { break }

                // Word boundary check
                let before = range.lowerBound == current.startIndex ||
                    !current[current.index(before: range.lowerBound)].isLetterOrDigit
                let after = range.upperBound == current.endIndex ||
                    !current[range.upperBound].isLetterOrDigit
                guard before && after else {
                    searchStart = range.upperBound
                    continue
                }

                let original = String(current[range])
                current.replaceSubrange(range, with: entry.replacement)
                corrections.append((original: original, corrected: entry.replacement, rule: "explicit"))

                let newEnd = current.index(range.lowerBound, offsetBy: entry.replacement.count)
                correctedRanges.append(range.lowerBound..<newEnd)
                searchStart = newEnd
            }
        }

        // Pass 2: Case normalization (multi-word first, then single-word)
        if !multiWordCaseLookup.isEmpty {
            let words = current.split(separator: " ", omittingEmptySubsequences: false)
            for windowSize in [3, 2] {
                guard words.count >= windowSize else { continue }
                var i = 0
                var wordStarts: [String.Index] = []
                // Compute word start indices in current string
                var idx = current.startIndex
                for word in words {
                    wordStarts.append(idx)
                    idx = current.index(idx, offsetBy: word.count)
                    if idx < current.endIndex { idx = current.index(after: idx) }
                }

                i = 0
                while i <= words.count - windowSize {
                    let windowWords = words[i..<(i + windowSize)]
                    let windowStr = windowWords.joined(separator: " ")
                    let windowLower = windowStr.lowercased()

                    if let canonical = multiWordCaseLookup[windowLower], canonical != windowStr {
                        let rangeStart = wordStarts[i]
                        let lastWordEnd = current.index(wordStarts[i + windowSize - 1],
                                                         offsetBy: words[i + windowSize - 1].count)
                        let range = rangeStart..<lastWordEnd

                        if !correctedRanges.contains(where: { $0.overlaps(range) }) {
                            let original = String(current[range])
                            current.replaceSubrange(range, with: canonical)
                            corrections.append((original: original, corrected: canonical, rule: "case"))
                            // Re-split after modification
                            break
                        }
                    }
                    i += 1
                }
            }
        }

        // Single-word case normalization
        let singleWords = current.split(separator: " ", omittingEmptySubsequences: false)
        var resultWords: [String] = []
        for word in singleWords {
            let wordStr = String(word)
            let lower = wordStr.lowercased()
            if let canonical = caseLookup[lower], canonical != wordStr {
                if let range = current.range(of: wordStr) {
                    if !correctedRanges.contains(where: { $0.overlaps(range) }) {
                        corrections.append((original: wordStr, corrected: canonical, rule: "case"))
                        resultWords.append(canonical)
                        continue
                    }
                }
            }
            resultWords.append(wordStr)
        }
        current = resultWords.joined(separator: " ")

        // Pass 3: Edit distance fuzzy match
        let fuzzyWords = current.split(separator: " ", omittingEmptySubsequences: false)
        var fuzzyResult: [String] = []
        for word in fuzzyWords {
            let wordStr = String(word)
            let stripped = wordStr.trimmingCharacters(in: .punctuationCharacters)

            guard stripped.count >= 4,
                  let first = stripped.first, first.isUppercase,
                  caseLookup[stripped.lowercased()] == nil else {
                fuzzyResult.append(wordStr)
                continue
            }

            // Check if this word was already corrected
            let wordLower = stripped.lowercased()
            if corrections.contains(where: { $0.corrected.lowercased().contains(wordLower) }) {
                fuzzyResult.append(wordStr)
                continue
            }

            var candidates: [(term: String, distance: Int)] = []
            for term in singleWordTerms {
                guard term.count >= 4 else { continue }
                let threshold = max(1, term.count / 4)
                let dist = Self.levenshtein(Array(stripped), Array(term))
                if dist > 0 && dist <= threshold {
                    candidates.append((term: term, distance: dist))
                }
            }

            if candidates.count == 1 {
                let match = candidates[0]
                let prefix = wordStr.prefix(while: { $0.isPunctuation })
                let suffix = wordStr.reversed().prefix(while: { $0.isPunctuation })
                let corrected = String(prefix) + match.term + String(suffix.reversed())
                corrections.append((original: wordStr, corrected: corrected, rule: "fuzzy"))
                fuzzyResult.append(corrected)
            } else {
                fuzzyResult.append(wordStr)
            }
        }
        current = fuzzyResult.joined(separator: " ")

        return Result(text: current, corrections: corrections)
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        let m = a.count
        let n = b.count
        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            prev = curr
        }
        return prev[n]
    }
}

private extension Character {
    var isLetterOrDigit: Bool {
        isLetter || isNumber
    }
}
