import Foundation
import SwiftParser
import SwiftSyntax

public struct SwiftFileSummary: Equatable, Sendable {
    public let imports: [ModuleName]
    public let publicDeclarations: [PublicDeclaration]
    public let storedProperties: [StoredProperty]
    public let enums: [DeclarationName]
    public let imperativeConstructs: [ImperativeConstruct]
    public let observedImperativeConstructs: [ObservedImperativeConstruct]
    public let syntaxFacts: SwiftSyntaxFactCatalog

    public init(
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

public struct SwiftFileParser: Sendable {
    public init() {}

    public func parse(_ source: String) -> SwiftFileSummary {
        let tree = Parser.parse(source: source)
        let visitor = SourceVisitor(locationConverter: SourceLocationConverter(fileName: "", tree: tree))
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
            imperativeConstructs: summary.imperativeConstructs,
            observedImperativeConstructs: summary.observedImperativeConstructs,
            syntaxFacts: summary.syntaxFacts
        )
    }
}

enum SwiftParseState: Equatable, Sendable {
    case scanning(
        imports: Set<ModuleName>,
        declarations: [PublicDeclaration],
        storedProperties: [StoredProperty],
        enums: [DeclarationName],
        observedImperativeConstructs: [ObservedImperativeConstruct],
        syntaxFacts: SwiftSyntaxFactCatalog
    )

    static let initial = SwiftParseState.scanning(
        imports: [],
        declarations: [],
        storedProperties: [],
        enums: [],
        observedImperativeConstructs: [],
        syntaxFacts: SwiftSyntaxFactCatalog()
    )

    var summary: SwiftFileSummary {
        switch self {
        case .scanning(let imports, let declarations, let storedProperties, let enums, let observedImperativeConstructs, let syntaxFacts):
            SwiftFileSummary(
                imports: Array(imports).sorted(by: { $0.rawValue < $1.rawValue }),
                publicDeclarations: declarations,
                storedProperties: storedProperties,
                enums: enums,
                imperativeConstructs: observedImperativeConstructs.map(\.construct),
                observedImperativeConstructs: observedImperativeConstructs,
                syntaxFacts: syntaxFacts
            )
        }
    }

    func importing(_ moduleName: ModuleName) -> SwiftParseState {
        switch self {
        case .scanning(let imports, let declarations, let storedProperties, let enums, let observedImperativeConstructs, let syntaxFacts):
            var nextImports = imports
            nextImports.insert(moduleName)
            return .scanning(
                imports: nextImports,
                declarations: declarations,
                storedProperties: storedProperties,
                enums: enums,
                observedImperativeConstructs: observedImperativeConstructs,
                syntaxFacts: syntaxFacts
            )
        }
    }

    func declaring(_ declaration: PublicDeclaration) -> SwiftParseState {
        switch self {
        case .scanning(let imports, let declarations, let storedProperties, let enums, let observedImperativeConstructs, let syntaxFacts):
            return .scanning(
                imports: imports,
                declarations: declarations + [declaration],
                storedProperties: storedProperties,
                enums: enums,
                observedImperativeConstructs: observedImperativeConstructs,
                syntaxFacts: syntaxFacts
            )
        }
    }

    func storing(_ property: StoredProperty) -> SwiftParseState {
        switch self {
        case .scanning(let imports, let declarations, let storedProperties, let enums, let observedImperativeConstructs, let syntaxFacts):
            return .scanning(
                imports: imports,
                declarations: declarations,
                storedProperties: storedProperties + [property],
                enums: enums,
                observedImperativeConstructs: observedImperativeConstructs,
                syntaxFacts: syntaxFacts
            )
        }
    }

    func seeingEnum(_ name: DeclarationName) -> SwiftParseState {
        switch self {
        case .scanning(let imports, let declarations, let storedProperties, let enums, let observedImperativeConstructs, let syntaxFacts):
            return .scanning(
                imports: imports,
                declarations: declarations,
                storedProperties: storedProperties,
                enums: enums + [name],
                observedImperativeConstructs: observedImperativeConstructs,
                syntaxFacts: syntaxFacts
            )
        }
    }

    func seeingImperativeConstruct(
        _ construct: ImperativeConstruct,
        location: SourcePosition? = nil
    ) -> SwiftParseState {
        switch self {
        case .scanning(let imports, let declarations, let storedProperties, let enums, let observedImperativeConstructs, let syntaxFacts):
            return .scanning(
                imports: imports,
                declarations: declarations,
                storedProperties: storedProperties,
                enums: enums,
                observedImperativeConstructs: observedImperativeConstructs + [
                    ObservedImperativeConstruct(construct: construct, location: location),
                ],
                syntaxFacts: syntaxFacts
            )
        }
    }

    func seeingSyntaxFact(_ fact: ObservedSyntaxFact) -> SwiftParseState {
        switch self {
        case .scanning(let imports, let declarations, let storedProperties, let enums, let observedImperativeConstructs, let syntaxFacts):
            return .scanning(
                imports: imports,
                declarations: declarations,
                storedProperties: storedProperties,
                enums: enums,
                observedImperativeConstructs: observedImperativeConstructs,
                syntaxFacts: syntaxFacts.adding(fact)
            )
        }
    }
}

private final class SourceVisitor: SyntaxAnyVisitor {
    private(set) var state = SwiftParseState.initial
    private let locationConverter: SourceLocationConverter

    init(locationConverter: SourceLocationConverter) {
        self.locationConverter = locationConverter
        super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        recordSyntax(node)
        return .visitChildren
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        let moduleName = node.bumper.importedModuleName
        if let moduleName, let typedModuleName = try? ModuleName(moduleName) {
            state = state.importing(typedModuleName)
        }
        return .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        record(kind: .class, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes, location: location(for: node))
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        record(kind: .struct, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes, location: location(for: node))
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        if let enumName = try? DeclarationName(node.name.text) {
            state = state.seeingEnum(enumName)
        }
        record(kind: .enum, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes, location: location(for: node))
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        record(kind: .protocol, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes, location: location(for: node))
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        record(kind: .actor, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes, location: location(for: node))
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        record(kind: .function, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes, location: location(for: node))
        if node.bumper.isMutatingDeclaration {
            state = state.seeingImperativeConstruct(.mutatingDeclaration, location: location(for: node))
        }
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        if node.bumper.isMutableBinding {
            state = state.seeingImperativeConstruct(.mutableBinding, location: location(for: node))
        }

        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
               let declarationName = try? DeclarationName(identifier.identifier.text) {
                if isPublic(node.modifiers) {
                    state = state.declaring(
                        PublicDeclaration(
                            kind: .variable,
                            name: declarationName,
                            attributes: attributeNames(node.attributes),
                            location: location(for: node)
                        )
                    )
                }
            }
        }

        for property in node.bumper.storedProperties {
            state = state.storing(
                StoredProperty(
                    name: property.name,
                    type: property.type,
                    isMutable: property.isMutable,
                    location: location(for: node)
                )
            )
        }

        return .skipChildren
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        state = state.seeingImperativeConstruct(.loop, location: location(for: node))
        return .visitChildren
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        state = state.seeingImperativeConstruct(.loop, location: location(for: node))
        return .visitChildren
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        state = state.seeingImperativeConstruct(.loop, location: location(for: node))
        return .visitChildren
    }

    override func visit(_ node: AssignmentExprSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        state = state.seeingImperativeConstruct(.assignment, location: location(for: node))
        return .visitChildren
    }

    override func visit(_ node: InOutExprSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        state = state.seeingImperativeConstruct(.inoutExpression, location: location(for: node))
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        if node.bumper.isDirectStringMatchingCall {
            state = state.seeingImperativeConstruct(.directStringMatch, location: location(for: node))
        }
        return .visitChildren
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        if node.bumper.isDirectStringComparison {
            state = state.seeingImperativeConstruct(.directStringMatch, location: location(for: node))
        }
        return .visitChildren
    }

    private func record(
        kind: DeclarationKind,
        name: String,
        modifiers: DeclModifierListSyntax,
        attributes: AttributeListSyntax,
        location: SourcePosition?
    ) {
        guard isPublic(modifiers), let declarationName = try? DeclarationName(name) else {
            return
        }

        state = state.declaring(
            PublicDeclaration(kind: kind, name: declarationName, attributes: attributeNames(attributes), location: location)
        )
    }

    private func isPublic(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { modifier in
            StringMatcher.exact("public").matches(modifier.name.text)
                || StringMatcher.exact("open").matches(modifier.name.text)
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

    private func recordSyntax(_ node: Syntax) {
        state = state.seeingSyntaxFact(
            ObservedSyntaxFact(
                family: family(for: node.kind),
                nodeKind: node.kind,
                spelling: spelling(for: node),
                location: location(for: node)
            )
        )
    }

    private func location(for node: some SyntaxProtocol) -> SourcePosition {
        let sourceLocation = locationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        return SourcePosition(line: sourceLocation.line, column: sourceLocation.column)
    }

    private func spelling(for node: Syntax) -> String? {
        switch family(for: node.kind) {
        case .attribute, .modifier, .importSyntax, .literal, .declaration, .typeSyntax, .pattern:
            node.trimmedDescription
        case .sourceFile, .trivia, .statement, .expression, .closure, .concurrency, .macro, .token, .unknown:
            nil
        }
    }

    private func family(for kind: SyntaxKind) -> SyntaxFactFamily {
        let name = String(describing: kind)
        let lowercasedName = name.lowercased()

        if kind == .sourceFile {
            return .sourceFile
        }

        if kind == .token {
            return .token
        }

        if StringMatcher.contains("import").matches(lowercasedName) {
            return .importSyntax
        }

        if StringMatcher.contains("attribute").matches(lowercasedName) {
            return .attribute
        }

        if StringMatcher.contains("modifier").matches(lowercasedName) {
            return .modifier
        }

        if StringMatcher.contains("macro").matches(lowercasedName) {
            return .macro
        }

        if StringMatcher.contains("closure").matches(lowercasedName) {
            return .closure
        }

        if StringMatcher.contains("literal").matches(lowercasedName) {
            return .literal
        }

        if StringMatcher.contains("await").matches(lowercasedName)
            || StringMatcher.contains("async").matches(lowercasedName)
            || StringMatcher.contains("actor").matches(lowercasedName)
            || StringMatcher.contains("isolated").matches(lowercasedName) {
            return .concurrency
        }

        if StringMatcher.suffix("Decl").matches(name) {
            return .declaration
        }

        if StringMatcher.suffix("Type").matches(name) {
            return .typeSyntax
        }

        if StringMatcher.suffix("Pattern").matches(name) {
            return .pattern
        }

        if StringMatcher.suffix("Stmt").matches(name) {
            return .statement
        }

        if StringMatcher.suffix("Expr").matches(name) {
            return .expression
        }

        return .unknown
    }
}
