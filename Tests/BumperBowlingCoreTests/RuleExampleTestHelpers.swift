import Foundation
import Testing
@testable import BumperBowlingCore

private let violationMarker: Character = "↓"

func verifyRule(
    _ rule: ArchitectureRule,
    configuration: ArchitectureConfiguration = BumperProjectConfiguration.configuration,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let description = rule.ruleDescription

    for example in description.nonTriggeringExamples {
        let violations = try await violations(for: rule, example: example, configuration: configuration)
        #expect(
            violations.isEmpty,
            "Expected no violations for \(description.id.rawValue), got \(violations.count)",
            sourceLocation: sourceLocation
        )
    }

    for example in description.triggeringExamples {
        let expectedCount = example.code.filter { $0 == violationMarker }.count
        let violations = try await violations(for: rule, example: example, configuration: configuration)

        #expect(
            violations.count == expectedCount,
            "Expected \(expectedCount) violation(s) for \(description.id.rawValue), got \(violations.count)",
            sourceLocation: sourceLocation
        )
        #expect(
            violations.allSatisfy { $0.ruleID == description.id },
            "Expected all violations to use rule id \(description.id.rawValue)",
            sourceLocation: sourceLocation
        )
    }
}

private func violations(
    for rule: ArchitectureRule,
    example: RuleExample,
    configuration: ArchitectureConfiguration
) async throws -> [ArchitectureViolation] {
    let source = String(example.code.filter { $0 != violationMarker })
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
    let fileURL = root.appendingPathComponent(example.path.rawValue)
    try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try source.write(to: fileURL, atomically: true, encoding: .utf8)

    let facts = try SwiftFileParser().parseFile(
        at: fileURL,
        relativePath: example.path,
        subsystem: example.subsystem
    )
    let rules = try ArchitectureRules(configuration: configuration)
    let repositoryFacts = RepositoryFacts(files: [facts])
    let graph = ArchitectureGraph(facts: repositoryFacts, rules: rules)

    return rule.evaluate(graph: graph, rules: rules)
}
