import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Self Lint")
struct SelfLintTests {
    @Test
    func bumperLintsItselfWithoutErrors() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let report = try await BumperCommands.lint(root: root)
        let messages = report.violations
            .filter { $0.severity == .error }
            .map { "\($0.path.rawValue): \($0.message) (\($0.ruleID.rawValue))" }

        for message in messages {
            Issue.record(Comment(rawValue: message))
        }
    }
}
