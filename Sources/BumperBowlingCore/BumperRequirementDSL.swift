import SwiftSyntax

public enum SourceFactRule: Hashable, Sendable {
    case disallowStoredProperty(StoredPropertyDisallowance)
    case disallowSyntaxConstruct(ImperativeConstruct)
    case requireSyntaxKind(SyntaxKind)
    case disallowSyntaxKind(SyntaxKind)
    case requireEnumStateMachine
}

public func RequireSyntax(_ kind: SyntaxKind) -> ComponentRequirement {
    ComponentRequirement(.requireSyntaxKind(kind))
}

public func DisallowSyntax(_ kind: SyntaxKind) -> ComponentRequirement {
    ComponentRequirement(.disallowSyntaxKind(kind))
}

public enum DeclarationFact: Sendable {}

public enum SyntaxKindFact: Sendable {}

public struct GraphPredicate<Fact>: Equatable, Sendable {
    public let erased: AnyGraphPredicate

    init(_ erased: AnyGraphPredicate) {
        self.erased = erased
    }
}

public enum AnyGraphPredicate: Equatable, Sendable {
    case declare(Set<StringMatcher>)
    case containSyntax(Set<SyntaxKind>)
}

public struct ComponentRequirement: Equatable, Sendable {
    public let factRules: Set<SourceFactRule>

    public init(_ factRules: SourceFactRule...) {
        self.factRules = Set(factRules)
    }

    public init(factRules: Set<SourceFactRule>) {
        self.factRules = factRules
    }

    public init(_ requirements: ComponentRequirement...) {
        self.init(requirements)
    }

    public init(_ requirements: [ComponentRequirement]) {
        self.factRules = requirements.reduce(into: Set<SourceFactRule>()) { partialResult, requirement in
            partialResult.formUnion(requirement.factRules)
        }
    }

    public func combined(with other: ComponentRequirement) -> ComponentRequirement {
        ComponentRequirement(factRules: factRules.union(other.factRules))
    }

    public static func all(_ requirements: ComponentRequirement...) -> ComponentRequirement {
        ComponentRequirement(requirements)
    }

    public static let noAnyStoredProperties = ComponentRequirement(.disallowStoredProperty(.any))
    public static let noBroadExistentialStoredProperties =
        ComponentRequirement(.disallowStoredProperty(.broadExistential))
    public static let noBoolStoredProperties = ComponentRequirement(.disallowStoredProperty(.boolState))
    public static let noOptionalStoredProperties = ComponentRequirement(.disallowStoredProperty(.optionalState))
    public static let noRawStringStoredProperties = ComponentRequirement(.disallowStoredProperty(.rawStringIdentity))
    public static let noStoredProperties = ComponentRequirement(.disallowStoredProperty(.storedProperty))
    public static let immutableStoredState = ComponentRequirement(.disallowStoredProperty(.storedVar))
    public static let enumStateMachine = ComponentRequirement(.requireEnumStateMachine)

    public static let explicitDomainSurfaces = ComponentRequirement(
        .noAnyStoredProperties,
        .noBroadExistentialStoredProperties
    )
    public static let typedIdentity = ComponentRequirement(.noRawStringStoredProperties)
    public static let computedState = ComponentRequirement(.noStoredProperties)
    public static let functionalCore = ComponentRequirement(
        .disallowSyntaxConstruct(.assignment),
        .disallowSyntaxConstruct(.loop),
        .disallowSyntaxConstruct(.mutableBinding),
        .disallowSyntaxConstruct(.inoutExpression),
        .disallowSyntaxConstruct(.mutatingDeclaration)
    )
    public static let swiftBasics = ComponentRequirement(
        .explicitDomainSurfaces,
        .typedIdentity,
        .immutableStoredState
    )
    public static let parserStateMachine = ComponentRequirement(.enumStateMachine)
    public static let pureDomain = ComponentRequirement(
        .swiftBasics,
        .functionalCore
    )
}

public func + (left: ComponentRequirement, right: ComponentRequirement) -> ComponentRequirement {
    left.combined(with: right)
}
