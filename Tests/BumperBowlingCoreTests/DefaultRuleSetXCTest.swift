import Foundation
import XCTest
@testable import BumperBowlingCore

final class DefaultRuleSetXCTest: XCTestCase {
    func testSwiftBasicsExamples() throws {
        try assertPasses(
            requirement: .swiftBasics,
            source: """
            struct User {
                let id: UserID
                let profile: UserProfile
            }
            """
        )

        try assertFails(
            requirement: .swiftBasics,
            source: """
            struct User {
                var id: String
                let payload: Any
                let service: any UserService
            }
            """,
            messages: [
                "Stored property id is mutable",
                "Stored property id uses raw String",
                "Stored property payload uses Any",
                "Stored property service uses a broad existential",
            ]
        )
    }

    func testFunctionalCoreExamples() throws {
        try assertPasses(
            requirement: .functionalCore,
            source: """
            func normalized(_ values: [Int]) -> [Int] {
                values
                    .filter { $0 > 0 }
                    .map { $0 * 2 }
            }
            """
        )

        try assertFails(
            requirement: .functionalCore,
            source: """
            func normalized(_ values: [Int]) -> [Int] {
                var result: [Int] = []
                for value in values {
                    result.append(value * 2)
                }
                return result
            }
            """,
            messages: [
                "Uses imperative construct mutableBinding",
                "Uses imperative construct loop",
            ]
        )
    }

    func testParserStateMachineExamples() throws {
        try assertPasses(
            requirement: .parserStateMachine,
            path: "Sources/Core/ThingParser.swift",
            source: """
            enum ParserState {
                case scanning([Token])
                case finished(AST)
            }

            struct Parser {}
            """
        )

        try assertFails(
            requirement: .parserStateMachine,
            path: "Sources/Core/ThingParser.swift",
            source: """
            struct Parser {
                private var tokens: [Token]
            }
            """,
            messages: [
                "Parser file does not declare an enum state machine",
            ]
        )
    }

    func testPureDomainExamples() throws {
        try assertPasses(
            requirement: .pureDomain,
            source: """
            struct PriceRule {
                let id: RuleID

                func apply(to price: Price) -> Price {
                    price.discounted(by: id)
                }
            }
            """
        )

        try assertFails(
            requirement: .pureDomain,
            source: """
            struct PriceRule {
                var id: String

                mutating func apply(to price: inout Price) {
                    price = price.discounted(by: id)
                }
            }
            """,
            messages: [
                "Stored property id is mutable",
                "Stored property id uses raw String",
                "Uses imperative construct mutatingDeclaration",
                "Uses imperative construct mutableBinding",
                "Uses imperative construct assignment",
            ]
        )
    }

    func testComputedStateExamples() throws {
        try assertPasses(
            requirement: .computedState,
            source: """
            enum UserSummary {
                static func displayName(for user: User) -> String {
                    "\\(user.firstName) \\(user.lastName)"
                }
            }
            """
        )

        try assertFails(
            requirement: .computedState,
            source: """
            struct UserSummary {
                let displayName: String
            }
            """,
            messages: [
                "Stored property displayName is stored",
            ]
        )
    }

    private func assertPasses(
        requirement: ComponentRequirement,
        path: String = "Sources/Core/Example.swift",
        source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let report = try lint(requirement: requirement, path: path, source: source)
        XCTAssertTrue(report.violations.isEmpty, "Expected no violations, got \(report.violations)", file: file, line: line)
    }

    private func assertFails(
        requirement: ComponentRequirement,
        path: String = "Sources/Core/Example.swift",
        source: String,
        messages: Set<String>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let report = try lint(requirement: requirement, path: path, source: source)
        let actualMessages = Set(report.violations.map(\.message))
        XCTAssertEqual(actualMessages, messages, file: file, line: line)
    }

    private func lint(
        requirement: ComponentRequirement,
        path: String,
        source: String
    ) throws -> LintReport {
        let configuration = BumperConfiguration {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    Requires(requirement, severity: .error)
                }
            }
        }.architectureConfiguration
        let relativePath = try RelativeFilePath(path)
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let sourceFile = root.appendingPathComponent(relativePath.rawValue)
        try FileManager.default.createDirectory(
            at: sourceFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try source.write(to: sourceFile, atomically: true, encoding: .utf8)

        let facts = try SwiftFileParser().parseFile(
            at: sourceFile,
            relativePath: relativePath,
            subsystem: try SubsystemID("core")
        )
        return try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: [facts]))
    }
}
