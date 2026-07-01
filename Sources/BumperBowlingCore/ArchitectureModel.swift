import Foundation

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

    public init(
        path: RelativeFilePath,
        subsystem: SubsystemID,
        imports: [ModuleName],
        publicDeclarations: [PublicDeclaration],
        storedProperties: [StoredProperty] = [],
        enums: [DeclarationName] = [],
        imperativeConstructs: [ImperativeConstruct] = []
    ) {
        self.path = path
        self.subsystem = subsystem
        self.imports = imports
        self.publicDeclarations = publicDeclarations
        self.storedProperties = storedProperties
        self.enums = enums
        self.imperativeConstructs = imperativeConstructs
    }
}

public struct PublicDeclaration: Equatable, Sendable {
    public let kind: DeclarationKind
    public let name: DeclarationName
    public let attributes: [AttributeName]

    public init(kind: DeclarationKind, name: DeclarationName, attributes: [AttributeName] = []) {
        self.kind = kind
        self.name = name
        self.attributes = attributes
    }
}

public struct StoredProperty: Equatable, Sendable {
    public let name: DeclarationName
    public let type: TypeName?
    public let isMutable: Bool

    public init(name: DeclarationName, type: TypeName?, isMutable: Bool) {
        self.name = name
        self.type = type
        self.isMutable = isMutable
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
