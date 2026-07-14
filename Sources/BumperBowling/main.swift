import BumperBowlingCore
import Foundation

@main
struct BumperCLI {
    static func main() async {
        do {
            try await run()
        } catch let error as ExitCode {
            writeError(error.description)
            Foundation.exit(error.code)
        } catch let error as BumperError {
            writeError(error.description)
            Foundation.exit(1)
        } catch {
            writeError(String(describing: error))
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.first ?? "help"

        switch command {
        case "init":
            let root = URL(fileURLWithPath: arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
            try BumperCommands.initialize(at: root)
        case "scan":
            try await runScan(Array(arguments.dropFirst()))
        case "snapshot":
            let root = URL(fileURLWithPath: arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
            let snapshot = try BumperCommands.snapshot(root: root)
            FileHandle.standardOutput.write(Data(snapshot.utf8))
        case "lint":
            try await runLint(Array(arguments.dropFirst()))
        case "baseline":
            try await runBaseline(Array(arguments.dropFirst()))
        case "config":
            try runConfig(Array(arguments.dropFirst()))
        case "explain":
            try await runExplain(Array(arguments.dropFirst()))
        case "help", "--help", "-h":
            print(Self.help)
        default:
            throw ExitCode.usage("Unknown command: \(command)\n\n\(Self.help)")
        }
    }

    private static func runScan(_ arguments: [String]) async throws {
        let options = try CommandOptions.parse(arguments)
        let report = try await BumperCommands.scanReport(
            root: options.root,
            progress: progressReporter(enabled: options.progress)
        )
        try write(report.markdownSummary, orJSON: report, format: options.format)
    }

    private static func runLint(_ arguments: [String]) async throws {
        let options = try CommandOptions.parse(arguments)
        let run = try await BumperCommands.lintRun(
            root: options.root,
            progress: progressReporter(enabled: options.progress)
        )
        let baseline = try options.baselinePath.map(loadBaseline)
        let comparison = baseline.map { LintBaselineComparison(report: run.report, baseline: $0) }
        let effectiveReport = comparison?.effectiveReport ?? run.report
        let markdown = comparison?.markdownSummary ?? run.report.markdownSummary
        try write(markdown, orJSON: run.output(baseline: baseline), format: options.format)
        if options.failOn.shouldFail(effectiveReport) {
            throw ExitCode.validationFailed
        }
    }

    private static func runBaseline(_ arguments: [String]) async throws {
        let subcommand = arguments.first ?? "help"
        switch subcommand {
        case "create":
            let options = try CommandOptions.parse(Array(arguments.dropFirst()))
            guard let outputPath = options.outputPath else {
                throw ExitCode.usage("Usage: bumper baseline create [root] --output <path>")
            }
            let run = try await BumperCommands.lintRun(
                root: options.root,
                progress: progressReporter(enabled: options.progress)
            )
            let baseline = LintBaseline(report: run.report)
            try writeBaseline(baseline, to: URL(fileURLWithPath: outputPath))
            try write(
                "Wrote \(baseline.violations.count) baseline violation(s) to \(outputPath).",
                orJSON: baseline,
                format: options.format
            )
        case "help", "--help", "-h":
            print(Self.help)
        default:
            throw ExitCode.usage("Unknown baseline command: \(subcommand)\n\n\(Self.help)")
        }
    }

    private static func runConfig(_ arguments: [String]) throws {
        let root = URL(fileURLWithPath: arguments.first ?? FileManager.default.currentDirectoryPath)
        let report = try BumperCommands.checkConfiguration(root: root)
        print(report.summary)
        if !report.isValid {
            throw ExitCode.invalidConfiguration
        }
    }

    private static func runExplain(_ arguments: [String]) async throws {
        guard let path = arguments.first else {
            throw ExitCode.usage("Usage: bumper explain <path>")
        }
        let root = URL(fileURLWithPath: arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
        let report = try await BumperCommands.explain(path: URL(fileURLWithPath: path), root: root)
        print(report)
    }

    private static func progressReporter(enabled: Bool) -> BumperProgressReporter {
        guard enabled else {
            return .disabled
        }

        return BumperProgressReporter { message in
            writeError("[bumper] \(message)")
        }
    }

    private static func loadBaseline(from path: String) throws -> LintBaseline {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(LintBaseline.self, from: data)
    }

    private static func writeBaseline(_ baseline: LintBaseline, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try jsonData(for: baseline).write(to: url, options: .atomic)
    }

    private static func write<Value: Encodable>(_ markdown: String, orJSON value: Value, format: OutputFormat) throws {
        switch format {
        case .markdown:
            print(markdown)
        case .json:
            FileHandle.standardOutput.write(try jsonData(for: value))
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private static func jsonData<Value: Encodable>(for value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private static let help = """
    Bumper Bowling

    Usage:
      bumper init [root]
      bumper lint [root] [--format markdown|json] [--fail-on none|note|warning|error] [--baseline path] [--progress]
      bumper scan [root] [--format markdown|json] [--progress]
      bumper baseline create [root] --output path [--format markdown|json] [--progress]
      bumper snapshot [root]
      bumper config [root]
      bumper explain <path>

    Environment:
      BUMPER_CACHE_DIR    Directory for cached project runner packages.

    Security:
      BumperBowling.swift is a program, like Package.swift. Bumper compiles it
      into one cached project runner and executes it in a sealed-off process:
      no network, nowhere to write, an empty environment. `describe` returns
      the configuration; `evaluate` reads scanned sources over stdin and
      returns one rule report. The build is cached, so it runs once per
      change, not once per lint.

      `bumper config` loads the configuration and tells you whether it is valid.

      Compiling a stranger's configuration runs their build. Lint repositories
      you trust.
    """
}

private struct CommandOptions {
    let root: URL
    let format: OutputFormat
    let failOn: LintFailureThreshold
    let baselinePath: String?
    let outputPath: String?
    let progress: Bool

    static func parse(_ arguments: [String]) throws -> CommandOptions {
        var positionals: [String] = []
        var format = OutputFormat.markdown
        var failOn = LintFailureThreshold.error
        var baselinePath: String?
        var outputPath: String?
        var progress = false
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]
            switch argument {
            case "--format":
                let value = try value(after: argument, in: arguments, index: &index)
                guard let parsed = OutputFormat(rawValue: value) else {
                    throw ExitCode.usage("Unknown output format: \(value)")
                }
                format = parsed
            case "--fail-on":
                let value = try value(after: argument, in: arguments, index: &index)
                guard let parsed = LintFailureThreshold(rawValue: value) else {
                    throw ExitCode.usage("Unknown fail-on threshold: \(value)")
                }
                failOn = parsed
            case "--baseline":
                baselinePath = try value(after: argument, in: arguments, index: &index)
            case "--output":
                outputPath = try value(after: argument, in: arguments, index: &index)
            case "--progress":
                progress = true
            default:
                if argument.hasPrefix("--") {
                    throw ExitCode.usage("Unknown option: \(argument)")
                }
                positionals.append(argument)
            }
            index = arguments.index(after: index)
        }

        return CommandOptions(
            root: URL(fileURLWithPath: positionals.first ?? FileManager.default.currentDirectoryPath),
            format: format,
            failOn: failOn,
            baselinePath: baselinePath,
            outputPath: outputPath,
            progress: progress
        )
    }

    private static func value(
        after option: String,
        in arguments: [String],
        index: inout Array<String>.Index
    ) throws -> String {
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            throw ExitCode.usage("Missing value after \(option)")
        }
        index = valueIndex
        return arguments[valueIndex]
    }
}

private enum OutputFormat: String {
    case markdown
    case json
}

enum ExitCode: Error, CustomStringConvertible {
    case usage(String)
    case validationFailed
    case invalidConfiguration

    var description: String {
        switch self {
        case .usage(let message):
            message
        case .validationFailed:
            "Architecture validation failed."
        case .invalidConfiguration:
            "Configuration is invalid."
        }
    }

    var code: Int32 {
        switch self {
        case .usage:
            64
        case .validationFailed, .invalidConfiguration:
            1
        }
    }
}
