import Foundation
import SwiftSyntax

/// The one authored project entry point. `describe` serializes only the
/// typed scan and architecture configuration; `evaluate` uses the rules in
/// process, so the project itself is not Codable.
public struct BumperProject: Sendable {
    /// The serializable scan and architecture configuration.
    public let architecture: ArchitectureConfiguration
    /// Project-defined rule definitions. Built-in rules derive from
    /// `architecture` so both sides of the runner boundary agree on them.
    public let rules: RuleSet

    public init(@BumperProjectBuilder _ content: () -> [BumperProjectElement]) {
        var includedPaths: [String] = ["Sources"]
        var excludedPaths: [String] = [".build", "DerivedData"]
        var components: [ComponentConfiguration] = []
        var ruleConfiguration = RuleConfiguration()
        var definitions: [any RuleDefinition] = []

        for element in content() {
            switch element {
            case .architecture(let definition):
                components += definition.components
                ruleConfiguration = ruleConfiguration.merging(definition.rules)
            case .included(let paths):
                includedPaths = paths
            case .excluded(let paths):
                excludedPaths = paths
            case .rules(let elements):
                for rule in elements {
                    switch rule {
                    case .configured(let configuration):
                        ruleConfiguration = ruleConfiguration.merging(configuration)
                    case .defined(let rules):
                        definitions += rules
                    }
                }
            }
        }

        self.architecture = ArchitectureConfiguration(
            includedPaths: includedPaths,
            excludedPaths: excludedPaths,
            components: components,
            rules: ruleConfiguration
        )
        self.rules = RuleSet(rules: definitions)
    }

    /// Evaluates built-in and project rules over one bounded repository
    /// input, parsing each file exactly once. The runner's `evaluate` mode
    /// calls this; tests can call it directly.
    public func evaluate(_ input: RepositoryInput) throws -> RuleReport {
        let ruleSet = RuleSet(rules: BuiltInRules.rules(from: input.architecture.rules) + rules.rules)
        return try ruleSet.evaluate(
            configuration: input.architecture,
            repository: RepositorySyntax(input: input)
        )
    }
}

public enum BumperProjectElement: Sendable {
    case architecture(ArchitectureDefinition)
    case included([String])
    case excluded([String])
    case rules([ProjectRuleElement])
}

@resultBuilder
public enum BumperProjectBuilder {
    public static func buildExpression(_ expression: BumperProjectElement) -> BumperProjectElement {
        expression
    }

    public static func buildExpression(_ expression: Rules) -> BumperProjectElement {
        .rules(expression.elements)
    }

    public static func buildBlock(_ components: BumperProjectElement...) -> [BumperProjectElement] {
        components
    }
}

public func Included(@StringListBuilder _ content: () -> [String]) -> BumperProjectElement {
    .included(content())
}

public func Excluded(@StringListBuilder _ content: () -> [String]) -> BumperProjectElement {
    .excluded(content())
}

public func Architecture(@ArchitectureBuilder _ content: () -> [ComponentDeclaration]) -> BumperProjectElement {
    .architecture(ArchitectureDefinition(components: content()))
}

/// The typed architecture builder: the project's `ComponentKey` enum gives
/// `Component(.core)` and `MayDependOn(.core)` their context, so consumers
/// need no `ComponentID` adapters.
public func Architecture<Key: ComponentKey>(
    _ key: Key.Type,
    @TypedArchitectureBuilder<Key> _ content: () -> [ComponentDeclaration]
) -> BumperProjectElement {
    validateComponentKeys(key)
    return .architecture(ArchitectureDefinition(components: content()))
}

/// Every raw value must be nonempty, unique after normalization, and
/// representable as a `ComponentID`. A malformed key is a configuration
/// error, not a silent empty scope.
private func validateComponentKeys<Key: ComponentKey>(_ key: Key.Type) {
    var seen = Set<ComponentID>()
    for componentKey in Key.allCases {
        guard seen.insert(componentKey.componentID).inserted else {
            preconditionFailure("Component key '\(componentKey.rawValue)' duplicates another component ID.")
        }
    }
}

@resultBuilder
public enum TypedArchitectureBuilder<Key: ComponentKey> {
    public static func buildExpression(_ expression: TypedComponentDeclaration<Key>) -> ComponentDeclaration {
        expression.declaration
    }

    public static func buildBlock(_ components: ComponentDeclaration...) -> [ComponentDeclaration] {
        components
    }
}

/// A component declared with a project component key. The wrapper only
/// carries the key type so the builder can supply enum-case context.
public struct TypedComponentDeclaration<Key: ComponentKey>: Sendable {
    let declaration: ComponentDeclaration
}

public func Component<Key: ComponentKey>(
    _ key: Key,
    @TypedComponentBuilder<Key> _ content: () -> [ComponentElement]
) -> TypedComponentDeclaration<Key> {
    TypedComponentDeclaration(declaration: makeComponentConfiguration(key.componentID, elements: content()))
}

@resultBuilder
public enum TypedComponentBuilder<Key: ComponentKey> {
    public static func buildBlock(_ components: ComponentElement...) -> [ComponentElement] {
        components
    }

    public static func buildExpression(_ expression: TypedComponentElement<Key>) -> ComponentElement {
        expression.element
    }

    public static func buildExpression(_ expression: ComponentElement) -> ComponentElement {
        expression
    }

    public static func buildExpression(_ expression: DSLPathList) -> ComponentElement {
        .owns(expression.values)
    }

    public static func buildExpression(_ expression: DSLModuleList) -> ComponentElement {
        .modules(expression.values)
    }
}

/// A component element whose arguments are project component keys.
public struct TypedComponentElement<Key: ComponentKey>: Sendable {
    let element: ComponentElement
}

public func MayDependOn<Key: ComponentKey>(_ dependencies: Key...) -> TypedComponentElement<Key> {
    TypedComponentElement(element: .mayDependOn(dependencies.map(\.componentID)))
}

public func DoesNotDependOn<Key: ComponentKey>(_ dependencies: Key...) -> TypedComponentElement<Key> {
    TypedComponentElement(element: .doesNotDependOn(dependencies.map(\.componentID)))
}

public enum ProjectRuleElement: Sendable {
    case configured(RuleConfiguration)
    case defined([any RuleDefinition])
}

@resultBuilder
public enum ProjectRulesBuilder {
    public static func buildExpression(_ expression: RuleConfiguration) -> [ProjectRuleElement] {
        [.configured(expression)]
    }

    public static func buildExpression(_ expression: some RuleDefinition) -> [ProjectRuleElement] {
        [.defined([expression])]
    }

    public static func buildExpression(_ expression: [any RuleDefinition]) -> [ProjectRuleElement] {
        [.defined(expression)]
    }

    public static func buildExpression(_ expression: RuleSet) -> [ProjectRuleElement] {
        [.defined(expression.rules)]
    }

    public static func buildBlock(_ components: [ProjectRuleElement]...) -> [ProjectRuleElement] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [ProjectRuleElement]?) -> [ProjectRuleElement] {
        component ?? []
    }

    public static func buildEither(first component: [ProjectRuleElement]) -> [ProjectRuleElement] {
        component
    }

    public static func buildEither(second component: [ProjectRuleElement]) -> [ProjectRuleElement] {
        component
    }

    public static func buildArray(_ components: [[ProjectRuleElement]]) -> [ProjectRuleElement] {
        components.flatMap { $0 }
    }
}

@resultBuilder
public enum StringListBuilder {
    public static func buildBlock(_ components: [String]...) -> [String] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: String) -> [String] {
        [expression]
    }
}

public struct ArchitectureDefinition: Equatable, Sendable {
    public let components: [ComponentConfiguration]
    public let rules: RuleConfiguration

    public init(components: [ComponentDeclaration]) {
        self.components = components.map(\.component)
        self.rules = components
            .map(\.derivedRules)
            .combined()
    }
}

@resultBuilder
public enum ArchitectureBuilder {
    public static func buildBlock(_ components: ComponentDeclaration...) -> [ComponentDeclaration] {
        components
    }
}
