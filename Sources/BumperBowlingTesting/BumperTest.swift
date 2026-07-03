import BumperBowlingCore
import Foundation

public struct BumperTest: Sendable {
    public let configuration: ArchitectureConfiguration

    public init(configuration: ArchitectureConfiguration) {
        self.configuration = configuration
    }

    public func lint(root: URL) async throws -> LintReport {
        try await BumperCommands.lint(root: root, configuration: configuration)
    }

    public func scan(root: URL) async throws -> String {
        try await BumperCommands.scan(root: root, configuration: configuration)
    }

    public func snapshot() throws -> String {
        try BumperCommands.snapshot(configuration: configuration)
    }

    public func explain(path: URL, root: URL) async throws -> String {
        try await BumperCommands.explain(path: path, root: root, configuration: configuration)
    }

    public func errorMessages(root: URL) async throws -> [String] {
        let report = try await lint(root: root)
        return report.violations
            .filter { $0.severity == .error }
            .map { "\($0.path.rawValue): \($0.message) (\($0.ruleID.rawValue))" }
    }
}
