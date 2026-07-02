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
            modifier.name.text == "mutating"
        }
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
}
