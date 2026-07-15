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
        case "test":
            try runTest(Array(arguments.dropFirst()))
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
        if options.timings {
            for line in timingsSummary(run) {
                writeError("[bumper] \(line)")
            }
        }
        let baseline = try options.baselinePath.map(loadBaseline)
        let comparison = baseline.map { LintBaselineComparison(report: run.report, baseline: $0) }
        let effectiveReport = comparison?.effectiveReport ?? run.report
        let markdown = comparison?.markdownSummary ?? run.report.markdownSummary
        try write(markdown, orJSON: run.output(baseline: baseline), format: options.format)
        if options.failOn.shouldFail(effectiveReport) {
            throw ExitCode.validationFailed
        }
    }

    private static func runTest(_ arguments: [String]) throws {
        if arguments == ["--help"] || arguments == ["-h"] {
            print(Self.testHelp)
            return
        }
        guard arguments.count <= 1 else {
            throw ExitCode.usage(Self.testHelp)
        }
        if let argument = arguments.first, argument.hasPrefix("-") {
            throw ExitCode.usage("Unknown option: \(argument)\n\n\(Self.testHelp)")
        }

        let root = URL(fileURLWithPath: arguments.first ?? FileManager.default.currentDirectoryPath)
        let status = try BumperCommands.test(root: root)
        guard status == 0 else {
            throw ExitCode.consumerTestsFailed(status)
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

    private static func timingsSummary(_ run: LintRunResult) -> [String] {
        var lines: [String] = []
        if let phases = run.phases {
            lines.append(
                "Phases: prepare \(seconds(phases.prepareRulesSeconds)), "
                    + "scan \(seconds(phases.scanSeconds)), "
                    + "evaluate \(seconds(phases.evaluateSeconds))"
            )
        }
        guard let telemetry = run.telemetry else {
            return lines
        }
        lines.append("Evaluation total: \(seconds(telemetry.totalSeconds))")
        lines += measurementLines(label: "Slowest rules", measurements: telemetry.ruleSeconds)
        lines += measurementLines(label: "Slowest facts", measurements: telemetry.factSeconds)
        return lines
    }

    private static func measurementLines(
        label: String,
        measurements: [EvaluationTelemetry.Measurement]
    ) -> [String] {
        guard !measurements.isEmpty else {
            return []
        }
        let entries = measurements.prefix(10).map { measurement in
            "\(measurement.id) \(seconds(measurement.seconds))"
        }
        return ["\(label): \(entries.joined(separator: ", "))"]
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.3fs", value)
    }

    private static let help = """
    Bumper Bowling

    Usage:
      bumper init [root]
      bumper lint [root] [--format markdown|json] [--fail-on none|note|warning|error] [--baseline path] [--progress] [--timings]
      bumper test [root]
      bumper scan [root] [--format markdown|json] [--progress]
      bumper baseline create [root] --output path [--format markdown|json] [--progress]
      bumper snapshot [root]
      bumper config [root]
      bumper explain <path>

    Environment:
      BUMPER_CACHE_DIR                    Directory for cached project runner packages.
      BUMPER_EVALUATION_TIMEOUT_SECONDS   Evaluation budget for the project runner
                                          (default 60; positive finite seconds).
                                          `--timings` shows where evaluation time goes.
      BUMPER_RUNNER_BUILD_CONFIGURATION   Runner build configuration: release
                                          (default) or debug, for hosts where the
                                          one-time optimized build is too expensive.

    Security:
      BumperBowling.swift is a program, like Package.swift. Bumper compiles it
      into one cached project runner and executes it in a sealed-off process:
      no network, nowhere to write, an empty environment. `describe` returns
      the configuration; `evaluate` reads scanned sources over stdin and
      returns one rule report. The build is cached, so it runs once per
      change, not once per lint.

      `bumper config` loads the configuration and tells you whether it is valid.

      `bumper test` runs repository-owned Swift tests with normal process access,
      the same trust boundary as `swift test`.

      Compiling a stranger's configuration runs their build. Lint repositories
      you trust.
    """

    private static let testHelp = """
    Usage: bumper test [root]

    Runs repository-owned rule tests. Source-mode tests under `.bumper/Tests`
    use Bumper's generated test target; a `.bumper` Swift package runs through
    that package's ordinary `swift test` targets.
    """
}

private struct CommandOptions {
    let root: URL
    let format: OutputFormat
    let failOn: LintFailureThreshold
    let baselinePath: String?
    let outputPath: String?
    let progress: Bool
    let timings: Bool

    static func parse(_ arguments: [String]) throws -> CommandOptions {
        var positionals: [String] = []
        var format = OutputFormat.markdown
        var failOn = LintFailureThreshold.error
        var baselinePath: String?
        var outputPath: String?
        var progress = false
        var timings = false
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
            case "--timings":
                timings = true
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
            progress: progress,
            timings: timings
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
    case consumerTestsFailed(Int32)

    var description: String {
        switch self {
        case .usage(let message):
            message
        case .validationFailed:
            "Architecture validation failed."
        case .invalidConfiguration:
            "Configuration is invalid."
        case .consumerTestsFailed(let status):
            "Consumer rule tests failed with exit status \(status)."
        }
    }

    var code: Int32 {
        switch self {
        case .usage:
            64
        case .validationFailed, .invalidConfiguration:
            1
        case .consumerTestsFailed(let status):
            status > 0 && status <= 255 ? status : 1
        }
    }
}
