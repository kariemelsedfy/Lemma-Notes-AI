import Foundation

/// Lines up what the recogniser saw, character by character, with what the model that answered the question read.
///
/// The model reads handwriting far better than the on-device recogniser, so when it says the writing was `Ax + 3`
/// and the recogniser saw `4x + 3`, the first box is an `A`. This is the "I know this is an A" step: it returns the
/// model's character for each box it can be matched to. It refuses when the two readings are too different to trust.
enum ReadingAlignment {
    /// The model's character for each box index, or nil when the readings do not line up closely enough.
    static func labels(seen: [Character], confirmed text: String) -> [Int: Character]? {
        let heard = Array(text.filter { !$0.isWhitespace })
        guard !seen.isEmpty, !heard.isEmpty else { return nil }
        let rows = seen.count
        let columns = heard.count
        var cost = [[Int]](repeating: [Int](repeating: 0, count: columns + 1), count: rows + 1)
        for row in 0...rows { cost[row][0] = row }
        for column in 0...columns { cost[0][column] = column }
        for row in 1...rows {
            for column in 1...columns {
                let same = String(seen[row - 1]).lowercased() == String(heard[column - 1]).lowercased()
                cost[row][column] = min(
                    cost[row - 1][column - 1] + (same ? 0 : 1), cost[row - 1][column] + 1, cost[row][column - 1] + 1)
            }
        }
        // More than a few slips, or a third of the writing, and the two are not reading the same thing.
        guard cost[rows][columns] <= max(2, max(rows, columns) / 3) else { return nil }
        var labels: [Int: Character] = [:]
        var row = rows
        var column = columns
        while row > 0, column > 0 {
            let same = String(seen[row - 1]).lowercased() == String(heard[column - 1]).lowercased()
            if cost[row][column] == cost[row - 1][column - 1] + (same ? 0 : 1) {
                labels[row - 1] = heard[column - 1]
                row -= 1
                column -= 1
            } else if cost[row][column] == cost[row - 1][column] + 1 {
                row -= 1
            } else {
                column -= 1
            }
        }
        return labels
    }
}
