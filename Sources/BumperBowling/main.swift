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
      bumper explain <path>

    Security:
      lint, scan, snapshot, and explain compile BumperBowling.swift, then evaluate it
      in a sandboxed process with an empty environment, no network, and no writable
      paths. The evaluated configuration value is the only thing that crosses back.
      Compiling a hostile configuration is still running its build; prefer trusted
      repositories.
    """
}

enum ExitCode: Error, CustomStringConvertible {
    case usage(String)
    case validationFailed

    var description: String {
        switch self {
        case .usage(let message):
            message
        case .validationFailed:
            "Architecture validation failed."
        }
    }

    var code: Int32 {
        switch self {
        case .usage:
            64
        case .validationFailed:
            1
        }
    }
}
