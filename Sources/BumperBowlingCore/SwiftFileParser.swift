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

    init(facts: [CollectedSourceFact]) {
        let summary = SourceFactSummary(facts: facts)

        self.init(
            imports: summary.imports,
            publicDeclarations: summary.publicDeclarations,
            storedProperties: summary.storedProperties,
            enums: summary.enums,
            observedImperativeConstructs: summary.observedImperativeConstructs,
            syntaxFacts: summary.syntaxFacts
        )
    }
}

public struct SwiftFileParser: Sendable {
    public init() {}

    public func parse(_ source: String) -> SwiftFileSummary {
        let tree = Parser.parse(source: source)
        let visitor = SourceVisitor(locationConverter: SourceLocationConverter(fileName: "", tree: tree))
        visitor.walk(tree)

        return SwiftFileSummary(facts: visitor.facts)
    }

    public func parseFile(
        at url: URL,
        relativePath: RelativeFilePath,
        subsystem: SubsystemID
    ) throws -> SourceFileFacts {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw BumperError.unreadableFile(relativePath.rawValue)
        }

        let tree = Parser.parse(source: source)
        let visitor = SourceVisitor(locationConverter: SourceLocationConverter(fileName: relativePath.rawValue, tree: tree))
        visitor.walk(tree)

        return SourceFileFacts(
            path: relativePath,
            subsystem: subsystem,
            facts: visitor.facts
        )
    }
}

private final class SourceVisitor: SyntaxAnyVisitor {
    private(set) var facts: [CollectedSourceFact] = []
    private let locationConverter: SourceLocationConverter

    init(locationConverter: SourceLocationConverter) {
        self.locationConverter = locationConverter
        super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        if let module = node.bumper.importedModule {
            facts.append(.importModule(module))
        }
        return .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        facts.append(contentsOf: node.bumper.publicDeclarations(location: location(for: node)).map(CollectedSourceFact.publicDeclaration))
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        facts.append(contentsOf: node.bumper.publicDeclarations(location: location(for: node)).map(CollectedSourceFact.publicDeclaration))
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        if let enumName = node.bumper.enumDeclaration {
            facts.append(.enumDeclaration(enumName))
        }
        facts.append(contentsOf: node.bumper.publicDeclarations(location: location(for: node)).map(CollectedSourceFact.publicDeclaration))
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        facts.append(contentsOf: node.bumper.publicDeclarations(location: location(for: node)).map(CollectedSourceFact.publicDeclaration))
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        facts.append(contentsOf: node.bumper.publicDeclarations(location: location(for: node)).map(CollectedSourceFact.publicDeclaration))
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        let location = location(for: node)
        facts.append(contentsOf: node.bumper.publicDeclarations(location: location).map(CollectedSourceFact.publicDeclaration))
        facts.append(contentsOf: node.bumper.imperativeConstructs(location: location).map(CollectedSourceFact.imperativeConstruct))
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        let location = location(for: node)
        facts.append(contentsOf: node.bumper.imperativeConstructs(location: location).map(CollectedSourceFact.imperativeConstruct))
        facts.append(contentsOf: node.bumper.publicDeclarations(location: location).map(CollectedSourceFact.publicDeclaration))
        facts.append(contentsOf: node.bumper.storedProperties(location: location).map(CollectedSourceFact.storedProperty))

        return .skipChildren
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        facts.append(contentsOf: node.bumper.imperativeConstructs(location: location(for: node)).map(CollectedSourceFact.imperativeConstruct))
        return .visitChildren
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        facts.append(contentsOf: node.bumper.imperativeConstructs(location: location(for: node)).map(CollectedSourceFact.imperativeConstruct))
        return .visitChildren
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        facts.append(contentsOf: node.bumper.imperativeConstructs(location: location(for: node)).map(CollectedSourceFact.imperativeConstruct))
        return .visitChildren
    }

    override func visit(_ node: AssignmentExprSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        facts.append(contentsOf: node.bumper.imperativeConstructs(location: location(for: node)).map(CollectedSourceFact.imperativeConstruct))
        return .visitChildren
    }

    override func visit(_ node: InOutExprSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        facts.append(contentsOf: node.bumper.imperativeConstructs(location: location(for: node)).map(CollectedSourceFact.imperativeConstruct))
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        facts.append(contentsOf: node.bumper.imperativeConstructs(location: location(for: node)).map(CollectedSourceFact.imperativeConstruct))
        return .visitChildren
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        facts.append(contentsOf: node.bumper.imperativeConstructs(location: location(for: node)).map(CollectedSourceFact.imperativeConstruct))
        return .visitChildren
    }

    private func recordSyntax(_ node: Syntax) {
        facts.append(node.bumper.syntaxFact(location: location(for: node)))
    }

    private func location(for node: some SyntaxProtocol) -> SourcePosition {
        let sourceLocation = locationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        return SourcePosition(line: sourceLocation.line, column: sourceLocation.column)
    }
}
