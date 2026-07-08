import Foundation
import SwiftSyntax

public struct BumperConfiguration: Equatable, Sendable {
    public let architectureConfiguration: ArchitectureConfiguration

    public init(@BumperConfigurationBuilder _ content: () -> [BumperConfigurationElement]) {
        self.init(elements: content())
    }

    init(elements: [BumperConfigurationElement]) {
        var includedPaths: [String] = ["Sources"]
        var excludedPaths: [String] = [".build", "DerivedData"]
        var components: [ComponentConfiguration] = []
        var rules = RuleConfiguration()

        for element in elements {
            switch element {
            case .architecture(let definition):
                components = definition.components
                rules = rules.merging(definition.rules)
            case .included(let paths):
                includedPaths = paths
            case .excluded(let paths):
                excludedPaths = paths
            case .assertions(let configuredRules):
                rules = rules.merging(configuredRules)
            }
        }

        self.architectureConfiguration = ArchitectureConfiguration(
            includedPaths: includedPaths,
            excludedPaths: excludedPaths,
            components: components,
            rules: rules
        )
    }
}

public enum BumperConfigurationElement: Equatable, Sendable {
    case architecture(ArchitectureDefinition)
    case included([String])
    case excluded([String])
    case assertions(RuleConfiguration)
}

@resultBuilder
public enum BumperConfigurationBuilder {
    public static func buildBlock(_ components: BumperConfigurationElement...) -> [BumperConfigurationElement] {
        components
    }
}

public func Included(@StringListBuilder _ content: () -> [String]) -> BumperConfigurationElement {
    .included(content())
}

public func Excluded(@StringListBuilder _ content: () -> [String]) -> BumperConfigurationElement {
    .excluded(content())
}

public func Architecture(@ArchitectureBuilder _ content: () -> [ComponentDeclaration]) -> BumperConfigurationElement {
    .architecture(ArchitectureDefinition(components: content()))
}

public func Assertions(@AssertionsBuilder _ content: () -> [RuleConfiguration]) -> BumperConfigurationElement {
    .assertions(content().combined())
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
