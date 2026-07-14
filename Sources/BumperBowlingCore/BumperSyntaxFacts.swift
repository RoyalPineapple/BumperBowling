import SwiftSyntax

extension BumperSyntaxView {
    func syntaxNode(location: SourcePosition?, spelling: String?) -> CollectedSourceFact {
        .syntax(
            ObservedSyntaxNode(
                kind: node.kind,
                spelling: spelling,
                location: location,
                parentKind: Syntax(node).parent?.kind,
                ancestorKinds: ancestorKinds(for: node)
            )
        )
    }
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
