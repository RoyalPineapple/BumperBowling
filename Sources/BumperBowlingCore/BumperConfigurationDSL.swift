import Foundation
import SwiftSyntax

public struct BumperConfiguration: Equatable, Sendable {
    public let architectureConfiguration: ArchitectureConfiguration

    public init(@BumperConfigurationBuilder _ content: () -> [BumperConfigurationElement]) {
        var includedPaths: [String] = ["Sources"]
        var excludedPaths: [String] = [".build", "DerivedData"]
        var subsystems: [SubsystemConfiguration] = []
        var rules = RuleConfiguration()

        for element in content() {
            switch element {
            case .architecture(let definition):
                subsystems = definition.subsystems
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
            subsystems: subsystems,
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

public func Architecture(@ArchitectureBuilder _ content: () -> [ComponentConfiguration]) -> BumperConfigurationElement {
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
    public let subsystems: [SubsystemConfiguration]
    public let rules: RuleConfiguration

    public init(components: [ComponentConfiguration]) {
        self.subsystems = components.map(\.subsystem)
        self.rules = components
            .map(\.derivedRules)
            .combined()
    }
}

@resultBuilder
public enum ArchitectureBuilder {
    public static func buildBlock(_ components: ComponentConfiguration...) -> [ComponentConfiguration] {
        components
    }
}

public struct ComponentConfiguration: Equatable, Sendable {
    public let subsystem: SubsystemConfiguration
    public let derivedRules: RuleConfiguration
}

public func Component(
    _ id: SubsystemID,
    @ComponentBuilder _ content: () -> [ComponentElement]
) -> ComponentConfiguration {
    var paths: [String] = []
    var modules: [String] = []
    var dependencies: [String] = []
    var forbiddenDependencies: [String] = []
    var usePolicies: [ComponentUsePolicy] = []
    var requirements: [ComponentRequirementSetting] = []
    var disallowances: [ImperativeDisallowanceSetting] = []
    var graphAssertions: [ComponentGraphAssertion] = []

    for element in content() {
        switch element {
        case .owns(let values):
            paths.append(contentsOf: values)
        case .modules(let values):
            modules.append(contentsOf: values)
        case .mayDependOn(let values):
            dependencies.append(contentsOf: values.map(\.rawValue))
        case .doesNotDependOn(let values):
            forbiddenDependencies.append(contentsOf: values.map(\.rawValue))
        case .usePolicy(let values):
            usePolicies.append(contentsOf: values)
        case .requires(let values):
            requirements.append(contentsOf: values)
        case .disallows(let values):
            disallowances.append(contentsOf: values)
        case .graphAssertion(let values):
            graphAssertions.append(contentsOf: values)
        }
    }

    return ComponentConfiguration(
        subsystem: SubsystemConfiguration(
            name: id.rawValue,
            modules: modules,
            paths: paths,
            mayDependOn: dependencies,
            mustNotDependOn: forbiddenDependencies
        ),
        derivedRules: requirements.derivedRules(defaultPaths: paths)
            .merging(usePolicies.derivedRules(defaultPaths: paths))
            .merging(disallowances.derivedRules(defaultPaths: paths))
            .merging(graphAssertions.derivedRules(defaultPaths: paths))
    )
}

@resultBuilder
public enum ComponentBuilder {
    public static func buildBlock(_ components: ComponentElement...) -> [ComponentElement] {
        components
    }

    public static func buildExpression(_ expression: DSLPathList) -> ComponentElement {
        .owns(expression.values)
    }

    public static func buildExpression(_ expression: DSLModuleList) -> ComponentElement {
        .modules(expression.values)
    }

    public static func buildExpression(_ expression: ComponentElement) -> ComponentElement {
        expression
    }
}

public enum ComponentElement: Equatable, Sendable {
    case owns([String])
    case modules([String])
    case mayDependOn([SubsystemID])
    case doesNotDependOn([SubsystemID])
    case usePolicy([ComponentUsePolicy])
    case requires([ComponentRequirementSetting])
    case disallows([ImperativeDisallowanceSetting])
    case graphAssertion([ComponentGraphAssertion])
}

public enum ComponentUsePolicy: Equatable, Sendable {
    case mayUse(capabilities: Set<Capability>, severity: Severity)
    case doesNotUse(modules: [String], severity: Severity)
}

public enum Capability: CaseIterable, Equatable, Hashable, Sendable {
    case foundation
    case swiftUI
    case uiKit
    case persistence
    case networking
    case testing

    var modules: [String] {
        switch self {
        case .foundation:
            ["Foundation"]
        case .swiftUI:
            ["SwiftUI"]
        case .uiKit:
            ["UIKit"]
        case .persistence:
            ["CoreData", "SwiftData"]
        case .networking:
            ["FoundationNetworking"]
        case .testing:
            ["XCTest", "Testing"]
        }
    }
}

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

    fileprivate init(_ erased: AnyGraphPredicate) {
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

public struct ComponentRequirementSetting: Equatable, Sendable {
    public let requirement: ComponentRequirement
    public let severity: Severity
    public let paths: [String]
}

public struct ImperativeDisallowanceSetting: Equatable, Sendable {
    public let constructs: Set<ImperativeConstruct>
    public let severity: Severity
    public let paths: [String]
    public let excludedPaths: [String]

    public init(
        constructs: Set<ImperativeConstruct>,
        severity: Severity,
        paths: [String],
        excludedPaths: [String] = []
    ) {
        self.constructs = constructs
        self.severity = severity
        self.paths = paths
        self.excludedPaths = excludedPaths
    }
}

public enum GraphPredicateExpectation: Equatable, Sendable {
    case does
    case doesNot
}

public struct ComponentGraphAssertion: Equatable, Sendable {
    public let expectation: GraphPredicateExpectation
    public let predicate: AnyGraphPredicate
    public let severity: Severity
    public let paths: [String]
}

public func Owns(_ paths: String...) -> DSLPathList {
    DSLPathList(values: paths)
}

public func MayDependOn(_ dependencies: SubsystemID...) -> ComponentElement {
    .mayDependOn(dependencies)
}

public func DoesNotDependOn(_ dependencies: SubsystemID...) -> ComponentElement {
    .doesNotDependOn(dependencies)
}

public func MayUse(_ capabilities: Capability..., severity: Severity = .error) -> ComponentElement {
    .usePolicy([.mayUse(capabilities: Set(capabilities), severity: severity)])
}

public func DoesNotUse(_ modules: String..., severity: Severity = .error) -> ComponentElement {
    .usePolicy([.doesNotUse(modules: modules, severity: severity)])
}

public func DoesNotUse(_ capabilities: Capability..., severity: Severity = .error) -> ComponentElement {
    .usePolicy([.doesNotUse(modules: capabilities.flatMap(\.modules), severity: severity)])
}

public func Declare(_ matchers: StringMatcher...) -> GraphPredicate<DeclarationFact> {
    GraphPredicate(.declare(Set(matchers)))
}

public func Declare(_ names: String...) -> GraphPredicate<DeclarationFact> {
    GraphPredicate(.declare(knownDeclarationMatchers(names)))
}

public func ContainSyntax(_ kinds: SyntaxKind...) -> GraphPredicate<SyntaxKindFact> {
    GraphPredicate(.containSyntax(Set(kinds)))
}

public func Does<Fact>(_ predicate: GraphPredicate<Fact>, severity: Severity = .error) -> ComponentElement {
    .graphAssertion(
        [
            ComponentGraphAssertion(
                expectation: .does,
                predicate: predicate.erased,
                severity: severity,
                paths: []
            ),
        ]
    )
}

public func DoesNot<Fact>(_ predicate: GraphPredicate<Fact>, severity: Severity = .error) -> ComponentElement {
    .graphAssertion(
        [
            ComponentGraphAssertion(
                expectation: .doesNot,
                predicate: predicate.erased,
                severity: severity,
                paths: []
            ),
        ]
    )
}

public func Declares(_ names: String..., severity: Severity = .error) -> ComponentElement {
    Does(GraphPredicate<DeclarationFact>(.declare(knownDeclarationMatchers(names))), severity: severity)
}

public func Requires(_ requirements: ComponentRequirement..., severity: Severity = .error) -> ComponentElement {
    .requires(
        requirements.map { requirement in
            ComponentRequirementSetting(requirement: requirement, severity: severity, paths: [])
        }
    )
}

public func RequiresScoped(
    _ requirement: ComponentRequirement,
    _ paths: String...,
    severity: Severity = .error
) -> ComponentElement {
    .requires([ComponentRequirementSetting(requirement: requirement, severity: severity, paths: paths)])
}

public func Disallows(_ constructs: ImperativeConstruct..., severity: Severity = .error) -> ComponentElement {
    .disallows([ImperativeDisallowanceSetting(constructs: Set(constructs), severity: severity, paths: [])])
}

public func Disallows(
    _ construct: ImperativeConstruct,
    severity: Severity = .error,
    in paths: String...
) -> ComponentElement {
    .disallows([ImperativeDisallowanceSetting(constructs: [construct], severity: severity, paths: paths)])
}

public func NoDirectStringMatching(
    _ severity: Severity,
    paths: [String],
    except excludedPaths: [String] = []
) -> RuleConfiguration {
    RuleConfiguration(
        syntaxConstructs: SyntaxConstructRuleConfiguration(
            severity: severity,
            paths: paths,
            excludedPaths: excludedPaths,
            disallowedConstructs: [.directStringMatch]
        )
    )
}

@resultBuilder
public enum AssertionsBuilder {
    public static func buildBlock(_ components: RuleConfiguration...) -> [RuleConfiguration] {
        components
    }
}

public func DependencyBoundaries(_ severity: Severity) -> RuleConfiguration {
    RuleConfiguration(subsystemBoundary: severity)
}

public func SingleOwner(_ severity: Severity) -> RuleConfiguration {
    RuleConfiguration(duplicateOwnership: severity)
}

public func AcyclicDeclaredDependencies(_ severity: Severity) -> RuleConfiguration {
    RuleConfiguration(declaredDependencyCycle: severity)
}

public struct DSLPathList: Equatable, Sendable {
    public let values: [String]
}

public struct DSLModuleList: Equatable, Sendable {
    public let values: [String]
}

public func Paths(_ paths: String...) -> DSLPathList {
    DSLPathList(values: paths)
}

public func Modules(_ modules: String...) -> DSLModuleList {
    DSLModuleList(values: modules)
}

private extension Array where Element == RuleConfiguration {
    func combined() -> RuleConfiguration {
        reduce(RuleConfiguration()) { partialResult, configuration in
            partialResult.merging(configuration)
        }
    }
}

private extension Array where Element == ComponentRequirementSetting {
    func derivedRules(defaultPaths: [String]) -> RuleConfiguration {
        var storedPropertySeverity = Severity.off
        var storedPropertyDisallowances = Set<StoredPropertyDisallowance>()
        var storedPropertyPaths: [String] = []
        var syntaxConstructSeverity = Severity.off
        var disallowedSyntaxConstructs = Set<ImperativeConstruct>()
        var syntaxConstructPaths: [String] = []
        var syntaxKindSeverity = Severity.off
        var requiredSyntaxKinds = Set<SyntaxKind>()
        var disallowedSyntaxKinds = Set<SyntaxKind>()
        var syntaxKindPaths: [String] = []
        var enumStateMachine = PathRuleConfiguration()

        for setting in self {
            let scopedPaths = setting.paths.isEmpty ? defaultPaths : setting.paths

            let storedPropertyRules = setting.requirement.storedPropertyDisallowances
            if !storedPropertyRules.isEmpty {
                storedPropertySeverity = storedPropertySeverity.merging(setting.severity)
                storedPropertyPaths.append(contentsOf: scopedPaths)
                storedPropertyDisallowances.formUnion(storedPropertyRules)
            }

            let syntaxConstructRules = setting.requirement.disallowedSyntaxConstructs
            if !syntaxConstructRules.isEmpty {
                syntaxConstructSeverity = syntaxConstructSeverity.merging(setting.severity)
                syntaxConstructPaths.append(contentsOf: scopedPaths)
                disallowedSyntaxConstructs.formUnion(syntaxConstructRules)
            }

            let requiredKinds = setting.requirement.requiredSyntaxKinds
            let disallowedKinds = setting.requirement.disallowedSyntaxKinds
            if !requiredKinds.isEmpty || !disallowedKinds.isEmpty {
                syntaxKindSeverity = syntaxKindSeverity.merging(setting.severity)
                syntaxKindPaths.append(contentsOf: scopedPaths)
                requiredSyntaxKinds.formUnion(requiredKinds)
                disallowedSyntaxKinds.formUnion(disallowedKinds)
            }

            if setting.requirement.requiresEnumStateMachine {
                enumStateMachine = PathRuleConfiguration(
                    severity: enumStateMachine.severity.merging(setting.severity),
                    paths: enumStateMachine.paths + scopedPaths
                )
            }
        }

        return RuleConfiguration(
            storedProperties: StoredPropertyRuleConfiguration(
                severity: storedPropertySeverity,
                paths: Swift.Array(Set(storedPropertyPaths)).sorted(),
                disallowances: storedPropertyDisallowances
            ),
            syntaxConstructs: SyntaxConstructRuleConfiguration(
                severity: syntaxConstructSeverity,
                paths: Swift.Array(Set(syntaxConstructPaths)).sorted(),
                disallowedConstructs: disallowedSyntaxConstructs
            ),
            syntaxKinds: SyntaxKindRuleConfiguration(
                severity: syntaxKindSeverity,
                paths: Swift.Array(Set(syntaxKindPaths)).sorted(),
                requiredKinds: requiredSyntaxKinds,
                disallowedKinds: disallowedSyntaxKinds
            ),
            enumStateMachine: enumStateMachine
        )
    }
}

private extension ComponentRequirement {
    var storedPropertyDisallowances: Set<StoredPropertyDisallowance> {
        Set(factRules.compactMap { rule in
            switch rule {
            case .disallowStoredProperty(let disallowance):
                disallowance
            case .disallowSyntaxConstruct, .requireSyntaxKind, .disallowSyntaxKind, .requireEnumStateMachine:
                nil
            }
        })
    }

    var disallowedSyntaxConstructs: Set<ImperativeConstruct> {
        Set(factRules.compactMap { rule in
            switch rule {
            case .disallowSyntaxConstruct(let construct):
                construct
            case .disallowStoredProperty, .requireSyntaxKind, .disallowSyntaxKind, .requireEnumStateMachine:
                nil
            }
        })
    }

    var requiresEnumStateMachine: Bool {
        factRules.contains(.requireEnumStateMachine)
    }

    var requiredSyntaxKinds: Set<SyntaxKind> {
        Set(factRules.compactMap { rule in
            switch rule {
            case .requireSyntaxKind(let kind):
                kind
            case .disallowStoredProperty, .disallowSyntaxConstruct, .disallowSyntaxKind, .requireEnumStateMachine:
                nil
            }
        })
    }

    var disallowedSyntaxKinds: Set<SyntaxKind> {
        Set(factRules.compactMap { rule in
            switch rule {
            case .disallowSyntaxKind(let kind):
                kind
            case .disallowStoredProperty, .disallowSyntaxConstruct, .requireSyntaxKind, .requireEnumStateMachine:
                nil
            }
        })
    }
}

private extension Array where Element == ComponentUsePolicy {
    func derivedRules(defaultPaths: [String]) -> RuleConfiguration {
        var forbiddenImports: [RuleSetting] = []
        var mayUseCapabilities = Set<Capability>()
        var mayUseSeverity = Severity.off
        var hasMayUse = false

        for policy in self {
            switch policy {
            case .mayUse(let capabilities, let severity):
                hasMayUse = true
                mayUseCapabilities.formUnion(capabilities)
                mayUseSeverity = mayUseSeverity.merging(severity)
            case .doesNotUse(let modules, let severity):
                forbiddenImports.append(RuleSetting(severity: severity, values: modules, paths: defaultPaths))
            }
        }

        if hasMayUse {
            let knownModules = Set(Capability.allCases.flatMap(\.modules))
            let allowedModules = Set(mayUseCapabilities.flatMap(\.modules))
            let disallowedModules = Swift.Array<String>(knownModules.subtracting(allowedModules)).sorted()

            forbiddenImports.append(
                RuleSetting(severity: mayUseSeverity, values: disallowedModules, paths: defaultPaths)
            )
        }

        return RuleConfiguration(forbiddenImports: forbiddenImports)
    }
}

private extension Array where Element == ImperativeDisallowanceSetting {
    func derivedRules(defaultPaths: [String]) -> RuleConfiguration {
        var severity = Severity.off
        var paths: [String] = []
        var excludedPaths: [String] = []
        var constructs = Set<ImperativeConstruct>()

        for setting in self {
            severity = severity.merging(setting.severity)
            paths.append(contentsOf: setting.paths.isEmpty ? defaultPaths : setting.paths)
            excludedPaths.append(contentsOf: setting.excludedPaths)
            constructs.formUnion(setting.constructs)
        }

        guard !constructs.isEmpty else {
            return RuleConfiguration()
        }

        return RuleConfiguration(
            syntaxConstructs: SyntaxConstructRuleConfiguration(
                severity: severity,
                paths: Swift.Array(Set(paths)).sorted(),
                excludedPaths: Swift.Array(Set(excludedPaths)).sorted(),
                disallowedConstructs: constructs
            )
        )
    }
}

private extension Array where Element == ComponentGraphAssertion {
    func derivedRules(defaultPaths: [String]) -> RuleConfiguration {
        var declarationSeverity = Severity.off
        var declarationPaths: [String] = []
        var requiredNames = Set<StringMatcher>()
        var disallowedNames = Set<StringMatcher>()

        var syntaxKindSeverity = Severity.off
        var syntaxKindPaths: [String] = []
        var requiredKinds = Set<SyntaxKind>()
        var disallowedKinds = Set<SyntaxKind>()

        for assertion in self {
            let scopedPaths = assertion.paths.isEmpty ? defaultPaths : assertion.paths

            switch (assertion.expectation, assertion.predicate) {
            case (.does, .declare(let names)):
                guard !names.isEmpty else { continue }
                declarationSeverity = declarationSeverity.merging(assertion.severity)
                declarationPaths.append(contentsOf: scopedPaths)
                requiredNames.formUnion(names)
            case (.doesNot, .declare(let names)):
                guard !names.isEmpty else { continue }
                declarationSeverity = declarationSeverity.merging(assertion.severity)
                declarationPaths.append(contentsOf: scopedPaths)
                disallowedNames.formUnion(names)
            case (.does, .containSyntax(let kinds)):
                guard !kinds.isEmpty else { continue }
                syntaxKindSeverity = syntaxKindSeverity.merging(assertion.severity)
                syntaxKindPaths.append(contentsOf: scopedPaths)
                requiredKinds.formUnion(kinds)
            case (.doesNot, .containSyntax(let kinds)):
                guard !kinds.isEmpty else { continue }
                syntaxKindSeverity = syntaxKindSeverity.merging(assertion.severity)
                syntaxKindPaths.append(contentsOf: scopedPaths)
                disallowedKinds.formUnion(kinds)
            }
        }

        return RuleConfiguration(
            syntaxKinds: SyntaxKindRuleConfiguration(
                severity: syntaxKindSeverity,
                paths: Swift.Array(Set(syntaxKindPaths)).sorted(),
                requiredKinds: requiredKinds,
                disallowedKinds: disallowedKinds
            ),
            publicDeclarations: PublicDeclarationRuleConfiguration(
                severity: declarationSeverity,
                paths: Swift.Array(Set(declarationPaths)).sorted(),
                requiredNames: requiredNames,
                disallowedNames: disallowedNames
            )
        )
    }
}

private extension RuleConfiguration {
    func merging(_ other: RuleConfiguration) -> RuleConfiguration {
        RuleConfiguration(
            forbiddenImports: forbiddenImports + other.forbiddenImports,
            subsystemBoundary: other.subsystemBoundary.isConfigured ? other.subsystemBoundary : subsystemBoundary,
            duplicateOwnership: other.duplicateOwnership.isConfigured ? other.duplicateOwnership : duplicateOwnership,
            declaredDependencyCycle: other.declaredDependencyCycle.isConfigured
                ? other.declaredDependencyCycle
                : declaredDependencyCycle,
            storedProperties: storedProperties.merging(other.storedProperties),
            syntaxConstructs: syntaxConstructs.merging(other.syntaxConstructs),
            syntaxKinds: syntaxKinds.merging(other.syntaxKinds),
            publicDeclarations: publicDeclarations.merging(other.publicDeclarations),
            enumStateMachine: enumStateMachine.merging(other.enumStateMachine)
        )
    }
}

private extension StoredPropertyRuleConfiguration {
    func merging(_ other: StoredPropertyRuleConfiguration) -> StoredPropertyRuleConfiguration {
        StoredPropertyRuleConfiguration(
            severity: severity.merging(other.severity),
            paths: Array(Set(paths + other.paths)).sorted(),
            disallowances: disallowances.union(other.disallowances)
        )
    }
}

private extension SyntaxConstructRuleConfiguration {
    func merging(_ other: SyntaxConstructRuleConfiguration) -> SyntaxConstructRuleConfiguration {
        SyntaxConstructRuleConfiguration(
            severity: severity.merging(other.severity),
            paths: Array(Set(paths + other.paths)).sorted(),
            excludedPaths: Array(Set(excludedPaths + other.excludedPaths)).sorted(),
            disallowedConstructs: disallowedConstructs.union(other.disallowedConstructs)
        )
    }
}

private extension SyntaxKindRuleConfiguration {
    func merging(_ other: SyntaxKindRuleConfiguration) -> SyntaxKindRuleConfiguration {
        SyntaxKindRuleConfiguration(
            severity: severity.merging(other.severity),
            paths: Array(Set(paths + other.paths)).sorted(),
            requiredKinds: requiredKinds.union(other.requiredKinds),
            disallowedKinds: disallowedKinds.union(other.disallowedKinds)
        )
    }
}

private extension PublicDeclarationRuleConfiguration {
    func merging(_ other: PublicDeclarationRuleConfiguration) -> PublicDeclarationRuleConfiguration {
        PublicDeclarationRuleConfiguration(
            severity: severity.merging(other.severity),
            paths: Array(Set(paths + other.paths)).sorted(),
            requiredNames: requiredNames.union(other.requiredNames),
            disallowedNames: disallowedNames.union(other.disallowedNames)
        )
    }
}

private extension PathRuleConfiguration {
    func merging(_ other: PathRuleConfiguration) -> PathRuleConfiguration {
        PathRuleConfiguration(
            severity: severity.merging(other.severity),
            paths: Array(Set(paths + other.paths)).sorted()
        )
    }
}

private extension Severity {
    var isConfigured: Bool {
        self != .off
    }
}

private extension StoredPropertyRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty || !disallowances.isEmpty
    }
}

private extension SyntaxConstructRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty || !excludedPaths.isEmpty || !disallowedConstructs.isEmpty
    }
}

private extension SyntaxKindRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty || !requiredKinds.isEmpty || !disallowedKinds.isEmpty
    }
}

private extension PublicDeclarationRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty || !requiredNames.isEmpty || !disallowedNames.isEmpty
    }
}

private extension PathRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty
    }
}

public extension SubsystemID {
    static let core = knownSubsystemID("core")
    static let cli = knownSubsystemID("cli")
    static let app = knownSubsystemID("app")
    static let ui = knownSubsystemID("ui")
    static let tests = knownSubsystemID("tests")
}

private func knownSubsystemID(_ rawValue: String) -> SubsystemID {
    guard let id = try? SubsystemID(rawValue) else {
        preconditionFailure("Invalid built-in subsystem id: \(rawValue)")
    }

    return id
}

private func knownDeclarationMatchers(_ rawNames: [String]) -> Set<StringMatcher> {
    Set(
        rawNames.map { rawName in
            guard let name = try? DeclarationName(rawName) else {
                preconditionFailure("Invalid declaration name in Bumper DSL: \(rawName)")
            }

            return StringMatcher.exact(name.rawValue)
        }
    )
}
