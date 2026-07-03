import Foundation
import SwiftSyntax

enum CollectedSourceFact: Equatable, Sendable {
    case importModule(ModuleName)
    case nominalType(NominalType)
    case extensionDeclaration(ExtensionDeclaration)
    case publicDeclaration(PublicDeclaration)
    case storedProperty(StoredProperty)
    case enumDeclaration(DeclarationName)
    case imperativeConstruct(ObservedImperativeConstruct)
    case syntax(ObservedSyntaxFact)
}

struct SourceFactSummary: Sendable {
    let imports: [ModuleName]
    let nominalTypes: [NominalType]
    let extensionDeclarations: [ExtensionDeclaration]
    let publicDeclarations: [PublicDeclaration]
    let storedProperties: [StoredProperty]
    let enums: [DeclarationName]
    let observedImperativeConstructs: [ObservedImperativeConstruct]
    let syntaxFacts: SwiftSyntaxFactCatalog

    init(facts: [CollectedSourceFact]) {
        var imports = Set<ModuleName>()
        var nominalTypes: [NominalType] = []
        var extensionDeclarations: [ExtensionDeclaration] = []
        var publicDeclarations: [PublicDeclaration] = []
        var storedProperties: [StoredProperty] = []
        var enums: [DeclarationName] = []
        var observedImperativeConstructs: [ObservedImperativeConstruct] = []
        var syntaxFacts = SwiftSyntaxFactCatalog()

        for fact in facts {
            switch fact {
            case .importModule(let module):
                imports.insert(module)
            case .nominalType(let type):
                nominalTypes.append(type)
            case .extensionDeclaration(let declaration):
                extensionDeclarations.append(declaration)
            case .publicDeclaration(let declaration):
                publicDeclarations.append(declaration)
            case .storedProperty(let property):
                storedProperties.append(property)
            case .enumDeclaration(let name):
                enums.append(name)
            case .imperativeConstruct(let construct):
                observedImperativeConstructs.append(construct)
            case .syntax(let fact):
                syntaxFacts = syntaxFacts.adding(fact)
            }
        }

        self.imports = imports.sorted(by: { $0.rawValue < $1.rawValue })
        self.nominalTypes = nominalTypes
        self.extensionDeclarations = extensionDeclarations
        self.publicDeclarations = publicDeclarations
        self.storedProperties = storedProperties
        self.enums = enums
        self.observedImperativeConstructs = observedImperativeConstructs
        self.syntaxFacts = syntaxFacts
    }
}

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

public enum GraphScope: Equatable, Sendable {
    case all
    case paths(Set<RelativePathPrefix>)

    public init(paths: [RelativePathPrefix]) {
        self = paths.isEmpty ? .all : .paths(Set(paths))
    }

    public func contains(_ file: SourceFileFacts) -> Bool {
        switch self {
        case .all:
            true
        case .paths(let paths):
            paths.contains { $0.contains(file.path) }
        }
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

    public func files(in scope: GraphScope) -> [SourceFileFacts] {
        sourceFiles.filter { scope.contains($0) }
    }

    public func imports(in scope: GraphScope) -> [(file: SourceFileFacts, module: ModuleName)] {
        files(in: scope).flatMap { file in
            file.imports.map { module in
                (file: file, module: module)
            }
        }
    }

    public func nominalTypes(in scope: GraphScope) -> [(file: SourceFileFacts, type: NominalType)] {
        files(in: scope).flatMap { file in
            file.nominalTypes.map { type in
                (file: file, type: type)
            }
        }
    }

    public func extensions(in scope: GraphScope) -> [(file: SourceFileFacts, declaration: ExtensionDeclaration)] {
        files(in: scope).flatMap { file in
            file.extensionDeclarations.map { declaration in
                (file: file, declaration: declaration)
            }
        }
    }

    public func declarations(in scope: GraphScope) -> [(file: SourceFileFacts, declaration: PublicDeclaration)] {
        files(in: scope).flatMap { file in
            file.publicDeclarations.map { declaration in
                (file: file, declaration: declaration)
            }
        }
    }

    public func storedProperties(in scope: GraphScope) -> [(file: SourceFileFacts, property: StoredProperty)] {
        files(in: scope).flatMap { file in
            file.storedProperties.map { property in
                (file: file, property: property)
            }
        }
    }

    public func constructs(in scope: GraphScope) -> [(file: SourceFileFacts, construct: ObservedImperativeConstruct)] {
        files(in: scope).flatMap { file in
            file.observedImperativeConstructs.map { construct in
                (file: file, construct: construct)
            }
        }
    }

    public func syntaxFacts(in scope: GraphScope) -> [(file: SourceFileFacts, fact: ObservedSyntaxFact)] {
        files(in: scope).flatMap { file in
            file.syntaxFacts.facts.map { fact in
                (file: file, fact: fact)
            }
        }
    }
}

public struct SourceFileFacts: Equatable, Sendable {
    public let path: RelativeFilePath
    public let subsystem: SubsystemID
    public let imports: [ModuleName]
    public let nominalTypes: [NominalType]
    public let extensionDeclarations: [ExtensionDeclaration]
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
        nominalTypes: [NominalType] = [],
        extensionDeclarations: [ExtensionDeclaration] = [],
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
        self.nominalTypes = nominalTypes
        self.extensionDeclarations = extensionDeclarations
        self.publicDeclarations = publicDeclarations
        self.storedProperties = storedProperties
        self.enums = enums
        self.imperativeConstructs = imperativeConstructs.isEmpty
            ? observedConstructs.map(\.construct)
            : imperativeConstructs
        self.observedImperativeConstructs = observedConstructs
        self.syntaxFacts = syntaxFacts
    }

    init(path: RelativeFilePath, subsystem: SubsystemID, facts: [CollectedSourceFact]) {
        let summary = SourceFactSummary(facts: facts)

        self.init(
            path: path,
            subsystem: subsystem,
            imports: summary.imports,
            nominalTypes: summary.nominalTypes,
            extensionDeclarations: summary.extensionDeclarations,
            publicDeclarations: summary.publicDeclarations,
            storedProperties: summary.storedProperties,
            enums: summary.enums,
            observedImperativeConstructs: summary.observedImperativeConstructs,
            syntaxFacts: summary.syntaxFacts
        )
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

public struct NominalType: Equatable, Sendable {
    public let kind: DeclarationKind
    public let name: TypeName
    public let access: AccessLevel
    public let inheritedTypes: [TypeName]
    public let attributes: [AttributeName]
    public let location: SourcePosition?

    public init(
        kind: DeclarationKind,
        name: TypeName,
        access: AccessLevel = .internal,
        inheritedTypes: [TypeName] = [],
        attributes: [AttributeName] = [],
        location: SourcePosition? = nil
    ) {
        self.kind = kind
        self.name = name
        self.access = access
        self.inheritedTypes = inheritedTypes
        self.attributes = attributes
        self.location = location
    }
}

public struct ExtensionDeclaration: Equatable, Sendable {
    public let extendedType: TypeName
    public let access: AccessLevel
    public let inheritedTypes: [TypeName]
    public let attributes: [AttributeName]
    public let location: SourcePosition?

    public init(
        extendedType: TypeName,
        access: AccessLevel = .internal,
        inheritedTypes: [TypeName] = [],
        attributes: [AttributeName] = [],
        location: SourcePosition? = nil
    ) {
        self.extendedType = extendedType
        self.access = access
        self.inheritedTypes = inheritedTypes
        self.attributes = attributes
        self.location = location
    }
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
    public let owner: TypeName?
    public let name: DeclarationName
    public let type: TypeName?
    public let access: AccessLevel
    public let attributes: [AttributeName]
    public let isMutable: Bool
    public let location: SourcePosition?

    public init(
        owner: TypeName? = nil,
        name: DeclarationName,
        type: TypeName?,
        access: AccessLevel = .internal,
        attributes: [AttributeName] = [],
        isMutable: Bool,
        location: SourcePosition? = nil
    ) {
        self.owner = owner
        self.name = name
        self.type = type
        self.access = access
        self.attributes = attributes
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

public enum AccessLevel: String, Equatable, Sendable {
    case `private`
    case `fileprivate`
    case `internal`
    case `package`
    case `public`
    case open
}

public enum ImperativeConstruct: String, Equatable, Hashable, Sendable, Codable {
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
