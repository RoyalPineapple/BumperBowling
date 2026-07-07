import SwiftSyntax

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

public extension BumperSyntaxView where Node == ExprSyntax {
    var isStringLikeExpression: Bool {
        if node.is(StringLiteralExprSyntax.self) {
            return true
        }

        guard let memberAccess = node.as(MemberAccessExprSyntax.self) else {
            return false
        }

        let memberName = memberAccess.declName.baseName.text
        return ["rawValue", "text", "trimmedDescription"].contains(memberName)
    }
}

public extension BumperSyntaxView where Node == FunctionCallExprSyntax {
    var isDirectStringMatchingCall: Bool {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return false
        }

        if memberAccess.base.map({ $0.trimmedDescription == "StringMatcher" }) == true {
            return false
        }

        let memberName = memberAccess.declName.baseName.text
        if memberName == "hasPrefix" || memberName == "hasSuffix" {
            return true
        }

        guard memberName == "contains" else {
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
                  ["==", "!="].contains(binaryOperator.operator.text) else {
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
