import Foundation
import Intelligence

/// Runs the golden set against a provider and writes the metrics JSON CI diffs between runs.
///
/// `./scripts/eval.sh --provider mock` is the supported entry point; this is what it calls.
/// Only the mock provider exists today (M4-02 and M4-08 add the rest), and the runner refuses
/// an unknown provider rather than silently substituting one — a metrics file attributed to the
/// wrong tier is worse than no metrics file.
struct Arguments {
    var provider = "mock"
    var casesPath = "Fixtures/golden"
    var outputPath: String?

    static func parse(_ raw: [String]) throws -> Arguments {
        var arguments = Arguments()
        var index = 0
        while index < raw.count {
            switch raw[index] {
            case "--provider": arguments.provider = try value(after: index, in: raw)
            case "--cases": arguments.casesPath = try value(after: index, in: raw)
            case "--out": arguments.outputPath = try value(after: index, in: raw)
            default: throw EvalCommandError.unknownArgument(raw[index])
            }
            index += 2
        }
        return arguments
    }

    private static func value(after index: Int, in raw: [String]) throws -> String {
        guard index + 1 < raw.count else { throw EvalCommandError.missingValue(raw[index]) }
        return raw[index + 1]
    }
}

enum EvalCommandError: Error, CustomStringConvertible {
    case unknownArgument(String)
    case missingValue(String)
    case unsupportedProvider(String)
    case noCases(String)

    var description: String {
        switch self {
        case .unknownArgument(let name): "unknown argument \(name)"
        case .missingValue(let name): "\(name) needs a value"
        case .unsupportedProvider(let name):
            "no provider named '\(name)'. Only 'mock' exists until M4-02 lands."
        case .noCases(let path): "no eval cases at \(path)"
        }
    }
}

func loadCases(from directory: String) throws -> [EvalCase] {
    let url = URL(fileURLWithPath: directory)
    let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !files.isEmpty else { throw EvalCommandError.noCases(directory) }

    let decoder = JSONDecoder()
    return try files.map { try decoder.decode(EvalCase.self, from: try Data(contentsOf: $0)) }
}

let arguments = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
guard arguments.provider == "mock" else {
    throw EvalCommandError.unsupportedProvider(arguments.provider)
}

let cases = try loadCases(from: arguments.casesPath)
let report = await EvalRunner(provider: CannedEvalProvider()).run(cases, context: try EvalContext.make())
let json = try report.jsonData()

if let outputPath = arguments.outputPath {
    try json.write(to: URL(fileURLWithPath: outputPath))
    print("wrote \(outputPath)")
}
print(String(bytes: json, encoding: .utf8) ?? "")

let metrics = report.metrics
print(
    """

    \(metrics.caseCount) cases · read \(Int(metrics.readAccuracy * 100))% · \
    intent \(Int(metrics.intentAccuracy * 100))% · \
    p50 \(String(format: "%.3f", metrics.latencyP50))s · failures \(metrics.failureCount)
    """
)
