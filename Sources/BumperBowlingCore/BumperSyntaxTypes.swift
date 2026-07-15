import SwiftSyntax

/// Value-only facts derived from explicit Swift type syntax. Names remain
/// syntax spellings: Bumper does not claim type or alias resolution.
public struct TypeShape: Equatable, Sendable {
    public let spelling: String
    public let referencedTypeNames: Set<String>
    public let outerTypeName: String?
    public let attributes: Set<String>
    public let outerFunctionAttributes: Set<String>
    public let isFunction: Bool

    public init(
        spelling: String,
        referencedTypeNames: Set<String>,
        outerTypeName: String?,
        attributes: Set<String>,
        outerFunctionAttributes: Set<String>,
        isFunction: Bool
    ) {
        self.spelling = spelling
        self.referencedTypeNames = referencedTypeNames
        self.outerTypeName = outerTypeName
        self.attributes = attributes
        self.outerFunctionAttributes = outerFunctionAttributes
        self.isFunction = isFunction
    }

    public func references(_ name: StringMatcher) -> Bool {
        referencedTypeNames.contains { name.matches($0) }
    }

    public func hasAttribute(matching matcher: StringMatcher) -> Bool {
        attributes.contains { matcher.matches($0) }
    }
}

public extension BumperSyntaxView where Node == TypeSyntax {
    var typeShape: TypeShape {
        let referencedTypeNames = Set(
            node.descendants(of: IdentifierTypeSyntax.self).map(\.name.text)
        ).union(node.descendants(of: MemberTypeSyntax.self).map(\.name.text))
        return TypeShape(
            spelling: node.trimmedDescription,
            referencedTypeNames: referencedTypeNames,
            outerTypeName: transparentOuterTypeName(in: node),
            attributes: Set(node.descendants(of: AttributeSyntax.self).map { attribute in
                attribute.attributeName.trimmedDescription
            }),
            outerFunctionAttributes: outerFunctionAttributes(in: node),
            isFunction: containsFunctionType(node)
        )
    }
}

public extension BumperSyntaxView where Node == PatternBindingSyntax {
    var explicitTypeShape: TypeShape? {
        node.typeAnnotation?.type.bumper.typeShape
    }
}

public extension BumperSyntaxView where Node == TypeAliasDeclSyntax {
    var aliasedTypeShape: TypeShape {
        node.initializer.value.bumper.typeShape
    }
}

private func transparentOuterTypeName(in type: TypeSyntax) -> String? {
    if let optional = type.as(OptionalTypeSyntax.self) {
        return transparentOuterTypeName(in: optional.wrappedType)
    }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return transparentOuterTypeName(in: attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let element = tuple.elements.first {
        return transparentOuterTypeName(in: element.type)
    }
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        if isOptional(identifier), let wrapped = singleGenericArgument(of: identifier) {
            return transparentOuterTypeName(in: wrapped)
        }
        return identifier.name.text
    }
    return type.as(MemberTypeSyntax.self)?.name.text
}

private func containsFunctionType(_ type: TypeSyntax) -> Bool {
    if type.is(FunctionTypeSyntax.self) {
        return true
    }
    if let optional = type.as(OptionalTypeSyntax.self) {
        return containsFunctionType(optional.wrappedType)
    }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return containsFunctionType(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let element = tuple.elements.first {
        return containsFunctionType(element.type)
    }
    if let identifier = type.as(IdentifierTypeSyntax.self),
       isOptional(identifier),
       let wrapped = singleGenericArgument(of: identifier) {
        return containsFunctionType(wrapped)
    }
    return false
}

private func outerFunctionAttributes(in type: TypeSyntax) -> Set<String> {
    if let optional = type.as(OptionalTypeSyntax.self) {
        return outerFunctionAttributes(in: optional.wrappedType)
    }
    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let element = tuple.elements.first {
        return outerFunctionAttributes(in: element.type)
    }
    if let identifier = type.as(IdentifierTypeSyntax.self),
       isOptional(identifier),
       let wrapped = singleGenericArgument(of: identifier) {
        return outerFunctionAttributes(in: wrapped)
    }
    guard let attributed = type.as(AttributedTypeSyntax.self) else {
        return []
    }
    return Set(attributed.attributes.compactMap { element in
        element.as(AttributeSyntax.self)?.attributeName.trimmedDescription
    })
}

private func isOptional(_ type: IdentifierTypeSyntax) -> Bool {
    StringMatcher.exact("Optional").matches(type.name.text)
}

private func singleGenericArgument(of type: IdentifierTypeSyntax) -> TypeSyntax? {
    guard let arguments = type.genericArgumentClause?.arguments,
          arguments.count == 1,
          let argument = arguments.first else {
        return nil
    }
    guard case .type(let wrapped) = argument.argument else {
        return nil
    }
    return wrapped
}
