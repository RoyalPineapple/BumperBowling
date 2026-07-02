import Foundation
import SwiftParser
import SwiftSyntax

public struct SwiftFileSummary: Equatable, Sendable {
    public let imports: [ModuleName]
    public let publicDeclarations: [PublicDeclaration]
    public let storedProperties: [StoredProperty]
    public let enums: [DeclarationName]
    public let imperativeConstructs: [ImperativeConstruct]

    public init(
        imports: [ModuleName],
        publicDeclarations: [PublicDeclaration],
        storedProperties: [StoredProperty] = [],
        enums: [DeclarationName] = [],
        imperativeConstructs: [ImperativeConstruct] = []
    ) {
        self.imports = imports
        self.publicDeclarations = publicDeclarations
        self.storedProperties = storedProperties
        self.enums = enums
        self.imperativeConstructs = imperativeConstructs
    }
}

public struct SwiftFileParser: Sendable {
    public init() {}

    public func parse(_ source: String) -> SwiftFileSummary {
        let tree = Parser.parse(source: source)
        let visitor = SourceVisitor(viewMode: .sourceAccurate)
        visitor.walk(tree)

        return visitor.state.summary
    }

    public func parseFile(
        at url: URL,
        relativePath: RelativeFilePath,
        subsystem: SubsystemID
    ) throws -> SourceFileFacts {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw BumperError.unreadableFile(relativePath.rawValue)
        }

        let summary = parse(source)
        return SourceFileFacts(
            path: relativePath,
            subsystem: subsystem,
            imports: summary.imports,
            publicDeclarations: summary.publicDeclarations,
            storedProperties: summary.storedProperties,
            enums: summary.enums,
            imperativeConstructs: summary.imperativeConstructs
        )
    }
}

enum SwiftParseState: Equatable, Sendable {
    case scanning(
        imports: Set<ModuleName>,
        declarations: [PublicDeclaration],
        storedProperties: [StoredProperty],
        enums: [DeclarationName],
        imperativeConstructs: [ImperativeConstruct]
    )

    static let initial = SwiftParseState.scanning(
        imports: [],
        declarations: [],
        storedProperties: [],
        enums: [],
        imperativeConstructs: []
    )

    var summary: SwiftFileSummary {
        switch self {
        case .scanning(let imports, let declarations, let storedProperties, let enums, let imperativeConstructs):
            SwiftFileSummary(
                imports: Array(imports).sorted(by: { $0.rawValue < $1.rawValue }),
                publicDeclarations: declarations,
                storedProperties: storedProperties,
                enums: enums,
                imperativeConstructs: imperativeConstructs
            )
        }
    }

    func importing(_ moduleName: ModuleName) -> SwiftParseState {
        switch self {
        case .scanning(let imports, let declarations, let storedProperties, let enums, let imperativeConstructs):
            var nextImports = imports
            nextImports.insert(moduleName)
            return .scanning(
                imports: nextImports,
                declarations: declarations,
                storedProperties: storedProperties,
                enums: enums,
                imperativeConstructs: imperativeConstructs
            )
        }
    }

    func declaring(_ declaration: PublicDeclaration) -> SwiftParseState {
        switch self {
        case .scanning(let imports, let declarations, let storedProperties, let enums, let imperativeConstructs):
            return .scanning(
                imports: imports,
                declarations: declarations + [declaration],
                storedProperties: storedProperties,
                enums: enums,
                imperativeConstructs: imperativeConstructs
            )
        }
    }

    func storing(_ property: StoredProperty) -> SwiftParseState {
        switch self {
        case .scanning(let imports, let declarations, let storedProperties, let enums, let imperativeConstructs):
            return .scanning(
                imports: imports,
                declarations: declarations,
                storedProperties: storedProperties + [property],
                enums: enums,
                imperativeConstructs: imperativeConstructs
            )
        }
    }

    func seeingEnum(_ name: DeclarationName) -> SwiftParseState {
        switch self {
        case .scanning(let imports, let declarations, let storedProperties, let enums, let imperativeConstructs):
            return .scanning(
                imports: imports,
                declarations: declarations,
                storedProperties: storedProperties,
                enums: enums + [name],
                imperativeConstructs: imperativeConstructs
            )
        }
    }

    func seeingImperativeConstruct(_ construct: ImperativeConstruct) -> SwiftParseState {
        switch self {
        case .scanning(let imports, let declarations, let storedProperties, let enums, let imperativeConstructs):
            return .scanning(
                imports: imports,
                declarations: declarations,
                storedProperties: storedProperties,
                enums: enums,
                imperativeConstructs: imperativeConstructs + [construct]
            )
        }
    }
}

private final class SourceVisitor: SyntaxVisitor {
    private(set) var state = SwiftParseState.initial

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let moduleName = node.path.trimmedDescription.components(separatedBy: ".").first
        if let moduleName, let typedModuleName = try? ModuleName(moduleName) {
            state = state.importing(typedModuleName)
        }
        return .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        record(kind: .class, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(kind: .struct, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        if let enumName = try? DeclarationName(node.name.text) {
            state = state.seeingEnum(enumName)
        }
        record(kind: .enum, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        record(kind: .protocol, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        record(kind: .actor, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        record(kind: .function, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes)
        if node.modifiers.contains(where: { $0.name.text == "mutating" }) {
            state = state.seeingImperativeConstruct(.mutatingDeclaration)
        }
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.bindingSpecifier.tokenKind == .keyword(.var) {
            state = state.seeingImperativeConstruct(.mutableBinding)
        }

        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
               let declarationName = try? DeclarationName(identifier.identifier.text) {
                if isStoredMember(node, binding: binding) {
                    let type = binding.typeAnnotation.flatMap { try? TypeName($0.type.trimmedDescription) }
                    state = state.storing(
                        StoredProperty(
                            name: declarationName,
                            type: type,
                            isMutable: node.bindingSpecifier.tokenKind == .keyword(.var)
                        )
                    )
                }

                if isPublic(node.modifiers) {
                    state = state.declaring(
                        PublicDeclaration(
                            kind: .variable,
                            name: declarationName,
                            attributes: attributeNames(node.attributes)
                        )
                    )
                }
            }
        }

        return .skipChildren
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        state = state.seeingImperativeConstruct(.loop)
        return .visitChildren
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        state = state.seeingImperativeConstruct(.loop)
        return .visitChildren
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        state = state.seeingImperativeConstruct(.loop)
        return .visitChildren
    }

    override func visit(_ node: AssignmentExprSyntax) -> SyntaxVisitorContinueKind {
        state = state.seeingImperativeConstruct(.assignment)
        return .visitChildren
    }

    override func visit(_ node: InOutExprSyntax) -> SyntaxVisitorContinueKind {
        state = state.seeingImperativeConstruct(.inoutExpression)
        return .visitChildren
    }

    private func isStoredMember(_ node: VariableDeclSyntax, binding: PatternBindingSyntax) -> Bool {
        node.parent?.as(MemberBlockItemSyntax.self) != nil && binding.accessorBlock == nil
    }

    private func record(
        kind: DeclarationKind,
        name: String,
        modifiers: DeclModifierListSyntax,
        attributes: AttributeListSyntax
    ) {
        guard isPublic(modifiers), let declarationName = try? DeclarationName(name) else {
            return
        }

        state = state.declaring(
            PublicDeclaration(kind: kind, name: declarationName, attributes: attributeNames(attributes))
        )
    }

    private func isPublic(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { modifier in
            modifier.name.text == "public" || modifier.name.text == "open"
        }
    }

    private func attributeNames(_ attributes: AttributeListSyntax) -> [AttributeName] {
        attributes.compactMap { element in
            guard let name = element.as(AttributeSyntax.self)?.attributeName.trimmedDescription else {
                return nil
            }
            return try? AttributeName(name)
        }
    }
}
