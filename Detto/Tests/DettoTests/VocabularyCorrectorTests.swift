import XCTest
@testable import Detto

final class VocabularyCorrectorTests: XCTestCase {

    func testEmptyConfigurationActsAsPassthrough() {
        let corrector = VocabularyCorrector(terms: [], corrections: [:])
        let result = corrector.correct("hello world")
        XCTAssertEqual(result.text, "hello world")
        XCTAssertTrue(result.corrections.isEmpty)
    }

    func testExplicitCorrectionApplied() {
        let corrector = VocabularyCorrector(
            terms: [],
            corrections: ["Mulker": "Mulcair"]
        )
        let result = corrector.correct("Tom Mulker said hello")
        XCTAssertEqual(result.text, "Tom Mulcair said hello")
        XCTAssertEqual(result.corrections.count, 1)
        XCTAssertEqual(result.corrections.first?.rule, "explicit")
    }

    func testExplicitCorrectionIsCaseInsensitive() {
        let corrector = VocabularyCorrector(
            terms: [],
            corrections: ["Mulker": "Mulcair"]
        )
        let result = corrector.correct("tom mulker said hello")
        XCTAssertEqual(result.text, "tom Mulcair said hello")
    }

    func testExplicitCorrectionRespectsWordBoundaries() {
        let corrector = VocabularyCorrector(
            terms: [],
            corrections: ["Mulker": "Mulcair"]
        )
        let result = corrector.correct("Mulkermost is not a word")
        XCTAssertEqual(result.text, "Mulkermost is not a word")
        XCTAssertTrue(result.corrections.isEmpty)
    }

    func testSingleWordCaseNormalization() {
        let corrector = VocabularyCorrector(
            terms: ["Cowichan"],
            corrections: [:]
        )
        let result = corrector.correct("the cowichan valley")
        XCTAssertEqual(result.text, "the Cowichan valley")
        XCTAssertEqual(result.corrections.first?.rule, "case")
    }

    func testMultiWordCaseNormalization() {
        let corrector = VocabularyCorrector(
            terms: ["David Eby"],
            corrections: [:]
        )
        let result = corrector.correct("david eby announced today")
        XCTAssertEqual(result.text, "David Eby announced today")
        XCTAssertEqual(result.corrections.first?.rule, "case")
    }

    func testDiagnosticCountsReportTermsAndCorrections() {
        let corrector = VocabularyCorrector(
            terms: ["Cowichan", "David Eby"],
            corrections: ["Mulker": "Mulcair", "Bozool": "Bosenkool"]
        )
        XCTAssertEqual(corrector.correctionCount, 2)
        XCTAssertEqual(corrector.termCount, 4)
    }
}
