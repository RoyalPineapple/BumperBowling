import Foundation
import SwiftSyntax

public struct RepositoryFacts: Equatable, Sendable {
    public let files: [SourceFileFacts]
    public let dependencyEdges: Set<DependencyEdge>

    public init(files: [SourceFileFacts]) {
        self.files = files
        self.dependencyEdges = Set(
            files.flatMap { file in
                file.imports.map { importedModule in
                    DependencyEdge(sourceSubsystem: file.subsystem, importedModule: importedModule)
                }
            }
        )
    }
}

public struct ArchitectureGraph: Equatable, Sendable {
    public let sourceFiles: [SourceFileFacts]
    public let subsystemNodes: Set<SubsystemID>
    public let moduleImportEdges: Set<DependencyEdge>
    public let subsystemImportEdges: Set<SubsystemImportEdge>

    public init(facts: RepositoryFacts, rules: ArchitectureRules) {
        self.sourceFiles = facts.files
        self.subsystemNodes = Set(facts.files.map(\.subsystem))
        self.moduleImportEdges = facts.dependencyEdges
        self.subsystemImportEdges = Set(
            facts.files.flatMap { file in
                file.imports.compactMap { importedModule in
                    guard let targetSubsystem = rules.subsystemByModule[importedModule] else {
                        return nil
                    }

                    return SubsystemImportEdge(
                        sourceSubsystem: file.subsystem,
                        targetSubsystem: targetSubsystem,
                        importedModule: importedModule,
                        sourcePath: file.path
                    )
                }
            }
        )
    }
}

public struct SourceFileFacts: Equatable, Sendable {
    public let path: RelativeFilePath
    public let subsystem: SubsystemID
    public let imports: [ModuleName]
    public let publicDeclarations: [PublicDeclaration]
    public let storedProperties: [StoredProperty]
    public let enums: [DeclarationName]
    public let imperativeConstructs: [ImperativeConstruct]
    public let observedImperativeConstructs: [ObservedImperativeConstruct]
    public let syntaxFacts: SwiftSyntaxFactCatalog

    public init(
        path: RelativeFilePath,
        subsystem: SubsystemID,
        imports: [ModuleName],
        publicDeclarations: [PublicDeclaration],
        storedProperties: [StoredProperty] = [],
        enums: [DeclarationName] = [],
        imperativeConstructs: [ImperativeConstruct] = [],
        observedImperativeConstructs: [ObservedImperativeConstruct] = [],
        syntaxFacts: SwiftSyntaxFactCatalog = SwiftSyntaxFactCatalog()
    ) {
        let observedConstructs = observedImperativeConstructs.isEmpty
            ? imperativeConstructs.map { ObservedImperativeConstruct(construct: $0) }
            : observedImperativeConstructs
        self.path = path
        self.subsystem = subsystem
        self.imports = imports
        self.publicDeclarations = publicDeclarations
        self.storedProperties = storedProperties
        self.enums = enums
        self.imperativeConstructs = imperativeConstructs.isEmpty
            ? observedConstructs.map(\.construct)
            : imperativeConstructs
        self.observedImperativeConstructs = observedConstructs
        self.syntaxFacts = syntaxFacts
    }
}

public struct SwiftSyntaxFactCatalog: Equatable, Sendable {
    public let nodeKinds: Set<SyntaxKind>
    public let facts: Set<ObservedSyntaxFact>

    public init(
        nodeKinds: Set<SyntaxKind> = [],
        facts: Set<ObservedSyntaxFact> = []
    ) {
        self.nodeKinds = nodeKinds
        self.facts = facts
    }

    public func adding(_ fact: ObservedSyntaxFact) -> SwiftSyntaxFactCatalog {
        SwiftSyntaxFactCatalog(
            nodeKinds: nodeKinds.union([fact.nodeKind]),
            facts: facts.union([fact])
        )
    }
}

public struct ObservedSyntaxFact: Hashable, Sendable {
    public let family: SyntaxFactFamily
    public let nodeKind: SyntaxKind
    public let spelling: String?
    public let location: SourcePosition?

    public init(
        family: SyntaxFactFamily,
        nodeKind: SyntaxKind,
        spelling: String? = nil,
        location: SourcePosition? = nil
    ) {
        self.family = family
        self.nodeKind = nodeKind
        self.spelling = spelling
        self.location = location
    }
}

public enum SyntaxFactFamily: String, Equatable, Hashable, Sendable {
    case sourceFile
    case trivia
    case importSyntax
    case declaration
    case typeSyntax
    case pattern
    case statement
    case expression
    case closure
    case concurrency
    case macro
    case literal
    case attribute
    case modifier
    case token
    case unknown
}

public struct PublicDeclaration: Equatable, Sendable {
    public let kind: DeclarationKind
    public let name: DeclarationName
    public let attributes: [AttributeName]
    public let location: SourcePosition?

    public init(
        kind: DeclarationKind,
        name: DeclarationName,
        attributes: [AttributeName] = [],
        location: SourcePosition? = nil
    ) {
        self.kind = kind
        self.name = name
        self.attributes = attributes
        self.location = location
    }
}

public struct StoredProperty: Equatable, Sendable {
    public let name: DeclarationName
    public let type: TypeName?
    public let isMutable: Bool
    public let location: SourcePosition?

    public init(
        name: DeclarationName,
        type: TypeName?,
        isMutable: Bool,
        location: SourcePosition? = nil
    ) {
        self.name = name
        self.type = type
        self.isMutable = isMutable
        self.location = location
    }
}

public struct ObservedImperativeConstruct: Equatable, Sendable {
    public let construct: ImperativeConstruct
    public let location: SourcePosition?

    public init(construct: ImperativeConstruct, location: SourcePosition? = nil) {
        self.construct = construct
        self.location = location
    }
}

public struct SourcePosition: Equatable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    public var description: String {
        "\(line):\(column)"
    }
}

public struct DependencyEdge: Hashable, Sendable {
    public let sourceSubsystem: SubsystemID
    public let importedModule: ModuleName

    public init(sourceSubsystem: SubsystemID, importedModule: ModuleName) {
        self.sourceSubsystem = sourceSubsystem
        self.importedModule = importedModule
    }
}

public struct SubsystemImportEdge: Hashable, Sendable {
    public let sourceSubsystem: SubsystemID
    public let targetSubsystem: SubsystemID
    public let importedModule: ModuleName
    public let sourcePath: RelativeFilePath

    public init(
        sourceSubsystem: SubsystemID,
        targetSubsystem: SubsystemID,
        importedModule: ModuleName,
        sourcePath: RelativeFilePath
    ) {
        self.sourceSubsystem = sourceSubsystem
        self.targetSubsystem = targetSubsystem
        self.importedModule = importedModule
        self.sourcePath = sourcePath
    }
}

public enum DeclarationKind: String, Equatable, Sendable {
    case actor
    case `class`
    case `enum`
    case function
    case `protocol`
    case `struct`
    case variable
}

public enum ImperativeConstruct: String, Equatable, Hashable, Sendable {
    case assignment
    case directStringMatch
    case loop
    case mutableBinding
    case inoutExpression
    case mutatingDeclaration
}

public struct DeclarationName: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ConfigurationError.emptyDeclarationName
        }
        self.rawValue = normalized
    }

    public var description: String {
        rawValue
    }
}

public struct AttributeName: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ConfigurationError.emptyAttributeName
        }
        self.rawValue = normalized
    }

    public var description: String {
        rawValue
    }
}

public struct TypeName: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ConfigurationError.emptyTypeName
        }
        self.rawValue = normalized
    }

    public var description: String {
        rawValue
    }
}
