import SwiftSyntax

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

    if lowercasedName.contains("import") {
        return .importSyntax
    }

    if lowercasedName.contains("attribute") {
        return .attribute
    }

    if lowercasedName.contains("modifier") {
        return .modifier
    }

    if lowercasedName.contains("macro") {
        return .macro
    }

    if lowercasedName.contains("closure") {
        return .closure
    }

    if lowercasedName.contains("literal") {
        return .literal
    }

    if lowercasedName.contains("await")
        || lowercasedName.contains("async")
        || lowercasedName.contains("actor")
        || lowercasedName.contains("isolated") {
        return .concurrency
    }

    if name.hasSuffix("Decl") {
        return .declaration
    }

    if name.hasSuffix("Type") {
        return .typeSyntax
    }

    if name.hasSuffix("Pattern") {
        return .pattern
    }

    if name.hasSuffix("Stmt") {
        return .statement
    }

    if name.hasSuffix("Expr") {
        return .expression
    }

    return .unknown
}
