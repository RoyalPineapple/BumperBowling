import SwiftSyntax

public struct BumperSyntaxView<Node: SyntaxProtocol>: Sendable {
    public let node: Node

    public init(node: Node) {
        self.node = node
    }

    public var kind: SyntaxKind {
        node.kind
    }

    public var spelling: String {
        node.trimmedDescription
    }

    public func isA<OtherNode: SyntaxProtocol>(_ type: OtherNode.Type) -> Bool {
        node.is(type)
    }

    public func hasAncestor<Ancestor: SyntaxProtocol>(_ type: Ancestor.Type) -> Bool {
        node.ancestorOrSelf { syntax in
            syntax.as(type)
        } != nil
    }
}

public extension SyntaxProtocol {
    var bumper: BumperSyntaxView<Self> {
        BumperSyntaxView(node: self)
    }
}

public struct BumperSyntaxPredicate<Node: SyntaxProtocol>: Sendable {
    private let matchesNode: @Sendable (Node) -> Bool

    public init(_ matchesNode: @escaping @Sendable (Node) -> Bool) {
        self.matchesNode = matchesNode
    }

    public func callAsFunction(_ node: Node) -> Bool {
        matchesNode(node)
    }

    public func and(_ other: BumperSyntaxPredicate<Node>) -> BumperSyntaxPredicate<Node> {
        BumperSyntaxPredicate { node in
            self(node) && other(node)
        }
    }

    public func or(_ other: BumperSyntaxPredicate<Node>) -> BumperSyntaxPredicate<Node> {
        BumperSyntaxPredicate { node in
            self(node) || other(node)
        }
    }
}

public struct BumperSyntaxAssertion<Node: SyntaxProtocol>: Sendable {
    public let nodeType: Node.Type
    private let predicate: BumperSyntaxPredicate<Node>

    public init(
        _ nodeType: Node.Type,
        where predicate: BumperSyntaxPredicate<Node>
    ) {
        self.nodeType = nodeType
        self.predicate = predicate
    }

    public func evaluate(_ node: some SyntaxProtocol) -> Bool? {
        guard let typedNode = node.as(Node.self) else {
            return nil
        }

        return predicate(typedNode)
    }
}

extension BumperSyntaxView {
    func syntaxFact(location: SourcePosition?) -> CollectedSourceFact {
        .syntax(
            ObservedSyntaxFact(
                family: syntaxFactFamily(for: node.kind),
                nodeKind: node.kind,
                spelling: syntaxFactSpelling(for: node),
                location: location
            )
        )
    }
}

public extension BumperSyntaxPredicate {
    static var always: BumperSyntaxPredicate<Node> {
        BumperSyntaxPredicate { _ in true }
    }

    static var never: BumperSyntaxPredicate<Node> {
        BumperSyntaxPredicate { _ in false }
    }
}

public extension BumperSyntaxView where Node == AttributeSyntax {
    var attributeName: String {
        node.attributeName.trimmedDescription
    }
}

public extension BumperSyntaxView where Node == FunctionDeclSyntax {
    var isMutatingDeclaration: Bool {
        node.modifiers.contains { modifier in
            StringMatcher.exact("mutating").matches(modifier.name.text)
        }
    }
}

public extension BumperSyntaxView where Node == ExprSyntax {
    var isStringLikeExpression: Bool {
        if node.is(StringLiteralExprSyntax.self) {
            return true
        }

        guard let memberAccess = node.as(MemberAccessExprSyntax.self) else {
            return false
        }

        let memberName = memberAccess.declName.baseName.text
        return [
            StringMatcher.exact("rawValue"),
            .exact("text"),
            .exact("trimmedDescription"),
        ].contains { matcher in
            matcher.matches(memberName)
        }
    }
}

public extension BumperSyntaxView where Node == FunctionCallExprSyntax {
    var isDirectStringMatchingCall: Bool {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return false
        }

        if memberAccess.base.map({ StringMatcher.exact("StringMatcher").matches($0.trimmedDescription) }) == true {
            return false
        }

        let memberName = memberAccess.declName.baseName.text
        if StringMatcher.exact("hasPrefix").matches(memberName)
            || StringMatcher.exact("hasSuffix").matches(memberName) {
            return true
        }

        guard StringMatcher.exact("contains").matches(memberName) else {
            return false
        }

        return node.arguments.contains { argument in
            argument.expression.bumper.isStringLikeExpression
        }
    }
}

public extension BumperSyntaxView where Node == SequenceExprSyntax {
    var isDirectStringComparison: Bool {
        let elements = Array(node.elements)

        for index in elements.indices {
            guard let binaryOperator = elements[index].as(BinaryOperatorExprSyntax.self),
                  StringMatcher.exact("==").matches(binaryOperator.operator.text)
                    || StringMatcher.exact("!=").matches(binaryOperator.operator.text) else {
                continue
            }

            let left = index > elements.startIndex ? elements[elements.index(before: index)] : nil
            let right = index < elements.index(before: elements.endIndex) ? elements[elements.index(after: index)] : nil

            if left?.bumper.isStringLikeExpression == true || right?.bumper.isStringLikeExpression == true {
                return true
            }
        }

        return false
    }
}

public extension BumperSyntaxView where Node == IdentifierTypeSyntax {
    var typeName: String {
        node.name.text
    }
}

public extension BumperSyntaxView where Node == ImportDeclSyntax {
    var importedModuleName: String? {
        node.path.trimmedDescription.components(separatedBy: ".").first
    }

    var importedModule: ModuleName? {
        importedModuleName.flatMap { try? ModuleName($0) }
    }
}

extension BumperSyntaxView where Node == ClassDeclSyntax {
    func publicDeclarations(location: SourcePosition?) -> [PublicDeclaration] {
        publicDeclaration(kind: .class, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes, location: location)
    }
}

extension BumperSyntaxView where Node == StructDeclSyntax {
    func publicDeclarations(location: SourcePosition?) -> [PublicDeclaration] {
        publicDeclaration(kind: .struct, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes, location: location)
    }
}

extension BumperSyntaxView where Node == EnumDeclSyntax {
    var enumDeclaration: DeclarationName? {
        try? DeclarationName(node.name.text)
    }

    func publicDeclarations(location: SourcePosition?) -> [PublicDeclaration] {
        publicDeclaration(kind: .enum, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes, location: location)
    }
}

extension BumperSyntaxView where Node == ProtocolDeclSyntax {
    func publicDeclarations(location: SourcePosition?) -> [PublicDeclaration] {
        publicDeclaration(kind: .protocol, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes, location: location)
    }
}

extension BumperSyntaxView where Node == ActorDeclSyntax {
    func publicDeclarations(location: SourcePosition?) -> [PublicDeclaration] {
        publicDeclaration(kind: .actor, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes, location: location)
    }
}

extension BumperSyntaxView where Node == FunctionDeclSyntax {
    func publicDeclarations(location: SourcePosition?) -> [PublicDeclaration] {
        publicDeclaration(kind: .function, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes, location: location)
    }

    func imperativeConstructs(location: SourcePosition?) -> [ObservedImperativeConstruct] {
        isMutatingDeclaration
            ? [ObservedImperativeConstruct(construct: .mutatingDeclaration, location: location)]
            : []
    }
}

extension BumperSyntaxView where Node == ForStmtSyntax {
    func imperativeConstructs(location: SourcePosition?) -> [ObservedImperativeConstruct] {
        [ObservedImperativeConstruct(construct: .loop, location: location)]
    }
}

extension BumperSyntaxView where Node == WhileStmtSyntax {
    func imperativeConstructs(location: SourcePosition?) -> [ObservedImperativeConstruct] {
        [ObservedImperativeConstruct(construct: .loop, location: location)]
    }
}

extension BumperSyntaxView where Node == RepeatStmtSyntax {
    func imperativeConstructs(location: SourcePosition?) -> [ObservedImperativeConstruct] {
        [ObservedImperativeConstruct(construct: .loop, location: location)]
    }
}

extension BumperSyntaxView where Node == AssignmentExprSyntax {
    func imperativeConstructs(location: SourcePosition?) -> [ObservedImperativeConstruct] {
        [ObservedImperativeConstruct(construct: .assignment, location: location)]
    }
}

extension BumperSyntaxView where Node == InOutExprSyntax {
    func imperativeConstructs(location: SourcePosition?) -> [ObservedImperativeConstruct] {
        [ObservedImperativeConstruct(construct: .inoutExpression, location: location)]
    }
}

extension BumperSyntaxView where Node == FunctionCallExprSyntax {
    func imperativeConstructs(location: SourcePosition?) -> [ObservedImperativeConstruct] {
        isDirectStringMatchingCall
            ? [ObservedImperativeConstruct(construct: .directStringMatch, location: location)]
            : []
    }
}

extension BumperSyntaxView where Node == SequenceExprSyntax {
    func imperativeConstructs(location: SourcePosition?) -> [ObservedImperativeConstruct] {
        isDirectStringComparison
            ? [ObservedImperativeConstruct(construct: .directStringMatch, location: location)]
            : []
    }
}

public extension BumperSyntaxView where Node == PatternBindingSyntax {
    var identifierName: String? {
        node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
    }

    var explicitTypeName: String? {
        node.typeAnnotation?.type.trimmedDescription
    }

    var hasAccessorBlock: Bool {
        node.accessorBlock != nil
    }
}

public extension BumperSyntaxView where Node == VariableDeclSyntax {
    var isMutableBinding: Bool {
        node.bindingSpecifier.tokenKind == .keyword(.var)
    }

    var isImmutableBinding: Bool {
        node.bindingSpecifier.tokenKind == .keyword(.let)
    }

    var isMemberDeclaration: Bool {
        node.parent?.as(MemberBlockItemSyntax.self) != nil
    }

    var bindingNames: [String] {
        node.bindings.compactMap { binding in
            binding.bumper.identifierName
        }
    }

    var explicitTypeNames: [String] {
        node.bindings.compactMap { binding in
            binding.bumper.explicitTypeName
        }
    }

    var storedProperties: [StoredProperty] {
        guard isMemberDeclaration else {
            return []
        }

        return node.bindings.compactMap { binding in
            guard !binding.bumper.hasAccessorBlock,
                  let name = binding.bumper.identifierName,
                  let declarationName = try? DeclarationName(name) else {
                return nil
            }

            let typeName = binding.bumper.explicitTypeName.flatMap { try? TypeName($0) }
            return StoredProperty(name: declarationName, type: typeName, isMutable: isMutableBinding)
        }
    }

    func publicDeclarations(location: SourcePosition?) -> [PublicDeclaration] {
        guard isPublic(node.modifiers) else {
            return []
        }

        return node.bindings.compactMap { binding in
            guard let name = binding.bumper.identifierName,
                  let declarationName = try? DeclarationName(name) else {
                return nil
            }

            return PublicDeclaration(
                kind: .variable,
                name: declarationName,
                attributes: attributeNames(node.attributes),
                location: location
            )
        }
    }

    func storedProperties(location: SourcePosition?) -> [StoredProperty] {
        storedProperties.map { property in
            StoredProperty(
                name: property.name,
                type: property.type,
                isMutable: property.isMutable,
                location: location
            )
        }
    }

    func imperativeConstructs(location: SourcePosition?) -> [ObservedImperativeConstruct] {
        isMutableBinding
            ? [ObservedImperativeConstruct(construct: .mutableBinding, location: location)]
            : []
    }
}

private func publicDeclaration(
    kind: DeclarationKind,
    name: String,
    modifiers: DeclModifierListSyntax,
    attributes: AttributeListSyntax,
    location: SourcePosition?
) -> [PublicDeclaration] {
    guard isPublic(modifiers), let declarationName = try? DeclarationName(name) else {
        return []
    }

    return [
        PublicDeclaration(
            kind: kind,
            name: declarationName,
            attributes: attributeNames(attributes),
            location: location
        ),
    ]
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

private func syntaxFactSpelling(for node: some SyntaxProtocol) -> String? {
    switch syntaxFactFamily(for: node.kind) {
    case .attribute, .modifier, .importSyntax, .literal, .declaration, .typeSyntax, .pattern:
        node.trimmedDescription
    case .sourceFile, .trivia, .statement, .expression, .closure, .concurrency, .macro, .token, .unknown:
        nil
    }
}

private func syntaxFactFamily(for kind: SyntaxKind) -> SyntaxFactFamily {
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
