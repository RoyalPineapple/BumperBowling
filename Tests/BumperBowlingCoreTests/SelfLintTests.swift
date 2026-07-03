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

        let bumperTest = BumperTest(configuration: BumperProjectConfiguration.configuration)

        for message in try await bumperTest.errorMessages(root: root) {
            Issue.record(Comment(rawValue: message))
        }
    }
}
