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

        for violation in report.violations where violation.severity == .error {
            Issue.record(
                "\(violation.path.rawValue): \(violation.message) (\(violation.ruleID.rawValue))"
            )
        }
    }
}
