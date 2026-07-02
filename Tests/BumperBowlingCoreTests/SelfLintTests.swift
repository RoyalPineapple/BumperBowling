import Foundation
import Testing
import BumperBowlingTesting
@testable import BumperBowlingCore

@Suite("Self Lint")
struct SelfLintTests {
    @Test
    func bumperLintsItselfWithoutErrors() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let harness = BumperTestHarness(configuration: BumperProjectConfiguration.configuration)

        for message in try await harness.errorMessages(root: root) {
            Issue.record(Comment(rawValue: message))
        }
    }
}
