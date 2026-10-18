import Handwriting
import XCTest

@testable import Intelligence

final class SuperscriptReaderTests: XCTestCase {
    // A line of characters as (character, bottom edge, height), normalised with the origin at the bottom left.
    // swiftlint:disable:next large_tuple
    private func line(_ items: [(Character, CGFloat, CGFloat)]) -> [RecognizedCharacter] {
        var left: CGFloat = 0
        var characters: [RecognizedCharacter] = []
        for item in items {
            let box = CGRect(x: left, y: item.1, width: 0.04, height: item.2)
            characters.append(RecognizedCharacter(character: item.0, box: box))
            left += 0.05
        }
        return characters
    }

    func testARaisedDigitAfterXBecomesAPower() {
        let characters = line([("y", 0.2, 0.3), ("=", 0.3, 0.1), ("x", 0.3, 0.2), ("3", 0.45, 0.14)])
        XCTAssertEqual(SuperscriptReader.transcript(from: characters, fallback: "y=x3"), "y=x^3")
    }

    func testADigitOnTheLineIsNotAPower() {
        let characters = line([("2", 0.3, 0.2), ("x", 0.3, 0.2), ("3", 0.3, 0.2)])
        XCTAssertEqual(SuperscriptReader.transcript(from: characters, fallback: "2x3"), "2x3")
    }

    func testATallDigitNextToAShortLetterIsNotMistakenForAPower() {
        // `3` is taller than `x` but both sit on the baseline.
        let characters = line([("x", 0.3, 0.14), ("3", 0.3, 0.22)])
        XCTAssertEqual(SuperscriptReader.transcript(from: characters, fallback: "x3"), "x3")
    }

    func testARaisedTwoDigitRunIsBracketed() {
        let characters = line([("x", 0.3, 0.2), ("1", 0.5, 0.12), ("2", 0.5, 0.12), ("+", 0.3, 0.1), ("1", 0.3, 0.2)])
        XCTAssertEqual(SuperscriptReader.transcript(from: characters, fallback: "x12+1"), "x^(12)+1")
    }

    func testARaisedNumberAfterABracketIsAPower() {
        let characters = line([("(", 0.25, 0.3), ("x", 0.3, 0.2), (")", 0.25, 0.3), ("2", 0.5, 0.12)])
        XCTAssertEqual(SuperscriptReader.transcript(from: characters, fallback: "(x)2"), "(x)^2")
    }

    func testMismatchedBoxesFallBackToTheTranscript() {
        let characters = line([("x", 0.3, 0.2), ("3", 0.5, 0.12)])
        XCTAssertEqual(SuperscriptReader.transcript(from: characters, fallback: "x^3 + 1"), "x^3 + 1")
        XCTAssertEqual(SuperscriptReader.transcript(from: [], fallback: "x3"), "x3")
    }
}
