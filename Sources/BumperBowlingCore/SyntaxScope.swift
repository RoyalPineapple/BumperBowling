import SwiftSyntax

/// Where a syntax node sits inside one source file.
public enum SyntaxPlacement: Equatable, Sendable {
    case fileScope
    case typeMember
    case local
}

/// Value-only lexical facts for one syntax node.
public struct LexicalContext: Equatable, Sendable {
    public let placement: SyntaxPlacement
    public let enclosingFunctionName: String?
    public let enclosingNominalNames: [String]
    public let enclosingExtensionName: String?
    public let isInsideProtocol: Bool

    public init(
        placement: SyntaxPlacement,
        enclosingFunctionName: String? = nil,
        enclosingNominalNames: [String] = [],
        enclosingExtensionName: String? = nil,
        isInsideProtocol: Bool = false
    ) {
        self.placement = placement
        self.enclosingFunctionName = enclosingFunctionName
        self.enclosingNominalNames = enclosingNominalNames
        self.enclosingExtensionName = enclosingExtensionName
        self.isInsideProtocol = isInsideProtocol
    }
}

/// A composable predicate over lexical facts. `RuleScope` selects files;
/// `SyntaxScope` selects nodes inside those files.
public struct SyntaxScope: Sendable {
    private let predicate: @Sendable (LexicalContext) -> Bool

    public init(_ includes: @escaping @Sendable (LexicalContext) -> Bool) {
        self.predicate = includes
    }

    public static let anywhere = SyntaxScope { _ in true }
    public static let fileScope = SyntaxScope { $0.placement == .fileScope }
    public static let typeMembers = SyntaxScope { $0.placement == .typeMember }
    public static let local = SyntaxScope { $0.placement == .local }
    public static let protocolMembers = SyntaxScope {
        $0.placement == .typeMember && $0.isInsideProtocol
    }

    public static func enclosed(in nominal: NominalSymbol) -> SyntaxScope {
        SyntaxScope { context in
            context.enclosingNominalNames.contains(nominal.name)
        }
    }

    public static func insideFunction(matching name: StringMatcher) -> SyntaxScope {
        SyntaxScope { context in
            context.enclosingFunctionName.map { name.matches($0) } == true
        }
    }

    public func union(_ other: SyntaxScope) -> SyntaxScope {
        SyntaxScope { context in
            self.includes(context) || other.includes(context)
        }
    }

    public func intersecting(_ other: SyntaxScope) -> SyntaxScope {
        SyntaxScope { context in
            self.includes(context) && other.includes(context)
        }
    }

    public func excluding(_ other: SyntaxScope) -> SyntaxScope {
        SyntaxScope { context in
            self.includes(context) && !other.includes(context)
        }
    }

    public func includes(_ context: LexicalContext) -> Bool {
        predicate(context)
    }
}

public extension BumperSyntaxView {
    var lexicalContext: LexicalContext {
        let ancestors = node.ancestors
        return LexicalContext(
            placement: syntaxPlacement(in: ancestors),
            enclosingFunctionName: ancestors.lazy.compactMap(functionName).first,
            enclosingNominalNames: ancestors.compactMap(nominalName),
            enclosingExtensionName: ancestors.lazy.compactMap(extensionName).first,
            isInsideProtocol: ancestors.contains { $0.is(ProtocolDeclSyntax.self) }
        )
    }
}

private func syntaxPlacement(in ancestors: [Syntax]) -> SyntaxPlacement {
    for ancestor in ancestors {
        if ancestor.is(CodeBlockSyntax.self) {
            return .local
        }
        if ancestor.is(MemberBlockItemSyntax.self) {
            return .typeMember
        }
        if ancestor.is(SourceFileSyntax.self) {
            return .fileScope
        }
    }
    return .fileScope
}

private func functionName(_ syntax: Syntax) -> String? {
    syntax.as(FunctionDeclSyntax.self)?.name.text
}

private func extensionName(_ syntax: Syntax) -> String? {
    syntax.as(ExtensionDeclSyntax.self)?.extendedType.trimmedDescription
}

private func nominalName(_ syntax: Syntax) -> String? {
    if let declaration = syntax.as(StructDeclSyntax.self) {
        return declaration.name.text
    }
    if let declaration = syntax.as(ClassDeclSyntax.self) {
        return declaration.name.text
    }
    if let declaration = syntax.as(EnumDeclSyntax.self) {
        return declaration.name.text
    }
    if let declaration = syntax.as(ActorDeclSyntax.self) {
        return declaration.name.text
    }
    if let declaration = syntax.as(ProtocolDeclSyntax.self) {
        return declaration.name.text
    }
    return extensionName(syntax)
}
