import SwiftSyntax

extension BumperSyntaxView {
    func syntaxNode(location: SourcePosition?) -> CollectedSourceFact {
        .syntax(
            ObservedSyntaxNode(
                kind: node.kind,
                spelling: syntaxNodeSpelling(for: node),
                location: location,
                parentKind: Syntax(node).parent?.kind,
                ancestorKinds: ancestorKinds(for: node)
            )
        )
    }
}

private func syntaxNodeSpelling(for node: some SyntaxProtocol) -> String? {
    let trimmed = node.trimmedDescription
    return trimmed.isEmpty ? nil : trimmed
}

private func ancestorKinds(for node: some SyntaxProtocol) -> [SyntaxKind] {
    var kinds: [SyntaxKind] = []
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        kinds.append(current.kind)
        ancestor = current.parent
    }
    return kinds
}
