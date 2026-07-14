import BumperBowlingCore
import Foundation

/// Evaluates exactly one rule over an in-memory repository and returns the
/// same structured report the engine and CLI use. Framework-neutral: no
/// XCTest or Swift Testing dependency.
public struct RuleTestHarness: Sendable {
    private let rules: RuleSet

    public init(_ rule: some RuleDefinition) {
        self.rules = RuleSet(rules: [rule])
    }

    /// Runs an explicitly supplied rule set instead of one rule.
    public init(_ rules: RuleSet) {
        self.rules = rules
    }

    public func evaluate(_ repository: VirtualRepository) throws -> RuleReport {
        let parser = SwiftFileParser()
        let facts = RepositoryFacts(
            files: repository.files.map { file in
                sourceFileFacts(for: file, summary: parser.parse(file.source))
            }
        )
        return try rules.evaluate(
            configuration: configuration(for: repository),
            repository: RepositorySyntax(facts: facts)
        )
    }

    private func configuration(for repository: VirtualRepository) -> ArchitectureConfiguration {
        let componentPaths = Dictionary(grouping: repository.files, by: \.component)
        return ArchitectureConfiguration(
            components: componentPaths
                .sorted { lhs, rhs in lhs.key.rawValue < rhs.key.rawValue }
                .map { component, files in
                    ComponentConfiguration(
                        name: component.rawValue,
                        paths: files.map(\.path.rawValue)
                    )
                }
        )
    }

    private func sourceFileFacts(for file: VirtualSourceFile, summary: SwiftFileSummary) -> SourceFileFacts {
        SourceFileFacts(
            path: file.path,
            component: file.component,
            source: file.source,
            imports: summary.imports,
            nominalTypes: summary.nominalTypes,
            extensionDeclarations: summary.extensionDeclarations,
            publicDeclarations: summary.publicDeclarations,
            storedProperties: summary.storedProperties,
            enums: summary.enums,
            observedImperativeConstructs: summary.observedImperativeConstructs,
            syntaxNodes: summary.syntaxNodes
        )
    }
}
