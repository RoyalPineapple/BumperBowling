import Foundation
import Testing
@testable import BumperBowlingCore

private let violationMarker: Character = "↓"

struct SourceFixture: Sendable {
    let files: [String: String]

    init(
        path: String = "Sources/Core/Fixture.swift",
        _ source: String
    ) {
        self.files = [path: source]
    }

    init(files: [String: String]) {
        self.files = files
    }
}

func assertRule(
    _ rule: ArchitectureRule,
    passing: SourceFixture,
    failing: SourceFixture,
    passingConfiguration: ArchitectureConfiguration = defaultRuleExampleConfiguration,
    failingConfiguration: ArchitectureConfiguration? = nil,
    expectedMessages: Set<String>,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let passingViolations = try await violations(for: rule, fixture: passing, configuration: passingConfiguration)
    #expect(
        passingViolations.isEmpty,
        "Expected passing fixture to produce no \(rule.id.rawValue) violations, got \(passingViolations.count).",
        sourceLocation: sourceLocation
    )

    let failingConfiguration = failingConfiguration ?? passingConfiguration
    let failingViolations = try await violations(for: rule, fixture: failing, configuration: failingConfiguration)
    let expectedCount = expectedMessages.count

    #expect(
        failingViolations.count == expectedCount,
        "Expected failing fixture to produce \(expectedCount) \(rule.id.rawValue) violation(s), got \(failingViolations.count).",
        sourceLocation: sourceLocation
    )
    #expect(
        failingViolations.allSatisfy { $0.ruleID == rule.id },
        "Expected all violations to use rule id \(rule.id.rawValue).",
        sourceLocation: sourceLocation
    )
    #expect(
        Set(failingViolations.map(\.message)) == expectedMessages,
        "Expected messages \(expectedMessages), got \(Set(failingViolations.map(\.message))).",
        sourceLocation: sourceLocation
    )

    let markerLocations = Set(failing.markedSources.flatMap(\.positions))
    if !markerLocations.isEmpty {
        let reportedLocations = failingViolations.compactMap(\.location)
        #expect(
            reportedLocations.allSatisfy { markerLocations.contains($0) },
            "Expected reported locations \(reportedLocations) to match marked locations \(markerLocations).",
            sourceLocation: sourceLocation
        )
    }
}

let defaultRuleExampleConfiguration = ArchitectureConfiguration(
    subsystems: [
        SubsystemConfiguration(name: "core", modules: ["Core"], paths: ["Sources/Core"]),
        SubsystemConfiguration(name: "ui", modules: ["UI"], paths: ["Sources/UI"]),
    ]
)

private func violations(
    for rule: ArchitectureRule,
    fixture: SourceFixture,
    configuration: ArchitectureConfiguration
) async throws -> [ArchitectureViolation] {
    let root = try writeFixture(fixture)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let rules = try ArchitectureRules(configuration: configuration)
    let facts = try await RepositoryScanner(rules: rules).scan(root: root)
    let graph = ArchitectureGraph(facts: facts, rules: rules)
    return rule.evaluate(graph: graph, rules: rules)
}

private func writeFixture(_ fixture: SourceFixture) throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)

    for markedSource in fixture.markedSources {
        let fileURL = root.appendingPathComponent(markedSource.path)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try markedSource.source.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    return root
}

private extension SourceFixture {
    var markedSources: [MarkedSource] {
        files.map { path, source in
            MarkedSource(path: path, markedSource: source)
        }
    }
}

private struct MarkedSource {
    let path: String
    let source: String
    let positions: [SourcePosition]

    init(path: String, markedSource: String) {
        self.path = path

        var source = ""
        var positions: [SourcePosition] = []
        var line = 1
        var column = 1

        for character in markedSource {
            if character == violationMarker {
                positions.append(SourcePosition(line: line, column: column))
                continue
            }

            source.append(character)
            if character == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }

        self.source = source
        self.positions = positions
    }
}
