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

}

public extension SyntaxProtocol {
    var bumper: BumperSyntaxView<Self> {
        BumperSyntaxView(node: self)
    }
}
