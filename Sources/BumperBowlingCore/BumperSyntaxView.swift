import SwiftSyntax

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
