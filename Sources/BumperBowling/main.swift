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
            let root = URL(fileURLWithPath: arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
            let report = try await BumperCommands.scan(root: root)
            print(report)
        case "snapshot":
            let root = URL(fileURLWithPath: arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
            let snapshot = try BumperCommands.snapshot(root: root)
            FileHandle.standardOutput.write(Data(snapshot.utf8))
        case "lint":
            let root = URL(fileURLWithPath: arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
            let report = try await BumperCommands.lint(root: root)
            print(report.markdownSummary)
            if report.hasErrors {
                throw ExitCode.validationFailed
            }
        case "config":
            let root = URL(fileURLWithPath: arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
            let report = try BumperCommands.checkConfiguration(root: root)
            print(report.summary)
            if !report.isValid {
                throw ExitCode.invalidConfiguration
            }
        case "explain":
            let remaining = Array(arguments.dropFirst())
            guard let path = remaining.first else {
                throw ExitCode.usage("Usage: bumper explain <path>")
            }
            let root = URL(fileURLWithPath: remaining.dropFirst().first ?? FileManager.default.currentDirectoryPath)
            let report = try await BumperCommands.explain(path: URL(fileURLWithPath: path), root: root)
            print(report)
        case "help", "--help", "-h":
            print(Self.help)
        default:
            throw ExitCode.usage("Unknown command: \(command)\n\n\(Self.help)")
        }
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private static let help = """
    Bumper Bowling

    Usage:
      bumper init [root]
      bumper lint [root]
      bumper scan [root]
      bumper snapshot [root]
      bumper config [root]
      bumper explain <path>

    Security:
      A BumperBowling.swift written in plain, familiar Swift is read as text and
      understood. It is never compiled and never run. A configuration fancier than
      that is compiled and run in a sealed-off process: no network, nowhere to
      write, an empty environment. Only the configuration value comes back.

      `bumper config` tells you which kind you have and whether it is valid.

      Compiling a stranger's configuration still runs their build. Lint
      repositories you trust.
    """
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
