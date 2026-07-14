import Foundation

/// The immutable parsed repository: per-file source facts plus parsed
/// source-file syntax. One parsed input feeds built-in and custom rules.
public struct RepositorySyntax: Sendable {
    /// Every scanned file's derived source facts.
    public let fileFacts: [CustomRuleFileFacts]
    /// Parsed syntax contexts for every file whose source text is available.
    public let files: [SourceFileContext]

    public init(files: [SourceFileContext]) {
        self.fileFacts = files.map(\.facts)
        self.files = files
    }

    /// Builds the parsed repository from scanned facts. Missing source text
    /// is an explicit analysis failure, not an empty match set.
    public init(facts: RepositoryFacts) throws {
        self.init(files: try facts.files.map(SourceFileContext.init))
    }

    init(fileFacts: [CustomRuleFileFacts], files: [SourceFileContext]) {
        self.fileFacts = fileFacts
        self.files = files
    }
}

/// Immutable repository, file, configuration, and fact access for one
/// evaluation run.
public struct RuleContext: Sendable {
    public let configuration: ArchitectureConfiguration
    public let repository: RepositorySyntax
    private let factStore: FactStore

    public init(configuration: ArchitectureConfiguration, repository: RepositorySyntax) {
        self.configuration = configuration
        self.repository = repository
        self.factStore = FactStore()
    }

    public func files(in scope: RuleScope) -> [SourceFileContext] {
        repository.files.filter { file in
            scope.includes(file)
        }
    }

    public func facts<Provider: FactProvider>(_ provider: Provider.Type) throws -> Provider.Facts {
        try factStore.facts(provider, repository: repository)
    }
}
