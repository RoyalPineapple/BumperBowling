import SwiftSyntax

public struct ComponentDeclaration: Equatable, Sendable {
    public let component: ComponentConfiguration
    public let derivedRules: RuleConfiguration
}

public struct ComponentShape: Equatable, Sendable {
    public let elements: [ComponentElement]

    public init(elements: [ComponentElement]) {
        self.elements = elements
    }

    public init(@ComponentBuilder _ content: () -> [ComponentElement]) {
        self.elements = content()
    }
}

public func Component(
    _ id: ComponentID,
    @ComponentBuilder _ content: () -> [ComponentElement]
) -> ComponentDeclaration {
    makeComponentConfiguration(id, elements: content())
}

func makeComponentConfiguration(
    _ id: ComponentID,
    elements: [ComponentElement]
) -> ComponentDeclaration {
    var paths: [String] = []
    var modules: [String] = []
    var dependencies: [String] = []
    var forbiddenDependencies: [String] = []
    var usePolicies: [ComponentUsePolicy] = []
    var requirements: [ComponentRequirementSetting] = []
    var disallowances: [ImperativeDisallowanceSetting] = []
    var graphAssertions: [ComponentGraphAssertion] = []

    for element in elements.flattened() {
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
        case .group:
            break
        }
    }

    return ComponentDeclaration(
        component: ComponentConfiguration(
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
    case mayDependOn([ComponentID])
    case doesNotDependOn([ComponentID])
    case usePolicy([ComponentUsePolicy])
    case requires([ComponentRequirementSetting])
    case disallows([ImperativeDisallowanceSetting])
    case graphAssertion([ComponentGraphAssertion])
    case group([ComponentElement])
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

public struct ComponentRequirementSetting: Equatable, Sendable {
    public let requirement: ComponentRequirement
    public let severity: Severity
    public let paths: [String]
    public let excludedPaths: [String]

    public init(
        requirement: ComponentRequirement,
        severity: Severity,
        paths: [String],
        excludedPaths: [String] = []
    ) {
        self.requirement = requirement
        self.severity = severity
        self.paths = paths
        self.excludedPaths = excludedPaths
    }
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

public func MayDependOn(_ dependencies: ComponentID...) -> ComponentElement {
    .mayDependOn(dependencies)
}

public func DoesNotDependOn(_ dependencies: ComponentID...) -> ComponentElement {
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

public func Applies(_ shape: ComponentShape) -> ComponentElement {
    .group(shape.elements)
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

public func ContainSyntaxNode(_ matchers: SyntaxNodeMatcher...) -> GraphPredicate<SyntaxNode> {
    GraphPredicate(.containSyntaxNode(Set(matchers)))
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

public func Requires(
    _ requirement: ComponentRequirement,
    except excludedPaths: [String],
    severity: Severity = .error
) -> ComponentElement {
    .requires([
        ComponentRequirementSetting(
            requirement: requirement,
            severity: severity,
            paths: [],
            excludedPaths: excludedPaths
        ),
    ])
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
private extension Array where Element == ComponentElement {
    func flattened() -> [ComponentElement] {
        flatMap { element in
            switch element {
            case .group(let elements):
                elements.flattened()
            case .owns,
                 .modules,
                 .mayDependOn,
                 .doesNotDependOn,
                 .usePolicy,
                 .requires,
                 .disallows,
                 .graphAssertion:
                [element]
            }
        }
    }
}

private extension Array where Element == ComponentRequirementSetting {
    func derivedRules(defaultPaths: [String]) -> RuleConfiguration {
        var storedPropertyRules: [StoredPropertyRuleConfiguration] = []
        var syntaxConstructRules: [SyntaxConstructRuleConfiguration] = []
        var syntaxKindRules: [SyntaxKindRuleConfiguration] = []
        var enumStateMachineRules: [PathRuleConfiguration] = []

        for setting in self {
            let scopedPaths = setting.paths.isEmpty ? defaultPaths : setting.paths

            let storedPropertyDisallowances = setting.requirement.storedPropertyDisallowances
            if !storedPropertyDisallowances.isEmpty {
                storedPropertyRules.append(
                    StoredPropertyRuleConfiguration(
                        severity: setting.severity,
                        paths: scopedPaths,
                        excludedPaths: setting.excludedPaths,
                        disallowances: storedPropertyDisallowances
                    )
                )
            }

            let disallowedSyntaxConstructs = setting.requirement.disallowedSyntaxConstructs
            if !disallowedSyntaxConstructs.isEmpty {
                syntaxConstructRules.append(
                    SyntaxConstructRuleConfiguration(
                        severity: setting.severity,
                        paths: scopedPaths,
                        disallowedConstructs: disallowedSyntaxConstructs
                    )
                )
            }

            let requiredKinds = setting.requirement.requiredSyntaxKinds
            let disallowedKinds = setting.requirement.disallowedSyntaxKinds
            if !requiredKinds.isEmpty || !disallowedKinds.isEmpty {
                syntaxKindRules.append(
                    SyntaxKindRuleConfiguration(
                        severity: setting.severity,
                        paths: scopedPaths,
                        requiredKinds: requiredKinds,
                        disallowedKinds: disallowedKinds
                    )
                )
            }

            if setting.requirement.requiresEnumStateMachine {
                enumStateMachineRules.append(
                    PathRuleConfiguration(
                        severity: setting.severity,
                        paths: scopedPaths
                    )
                )
            }
        }

        return RuleConfiguration(
            storedPropertyRules: storedPropertyRules,
            syntaxConstructRules: syntaxConstructRules,
            syntaxKindRules: syntaxKindRules,
            enumStateMachineRules: enumStateMachineRules
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
        var syntaxConstructRules: [SyntaxConstructRuleConfiguration] = []

        for setting in self {
            guard !setting.constructs.isEmpty else { continue }
            syntaxConstructRules.append(
                SyntaxConstructRuleConfiguration(
                    severity: setting.severity,
                    paths: setting.paths.isEmpty ? defaultPaths : setting.paths,
                    excludedPaths: setting.excludedPaths,
                    disallowedConstructs: setting.constructs
                )
            )
        }

        return RuleConfiguration(syntaxConstructRules: syntaxConstructRules)
    }
}

private extension Array where Element == ComponentGraphAssertion {
    func derivedRules(defaultPaths: [String]) -> RuleConfiguration {
        var publicDeclarationRules: [PublicDeclarationRuleConfiguration] = []
        var syntaxKindRules: [SyntaxKindRuleConfiguration] = []
        var syntaxNodeRules: [SyntaxNodeRuleConfiguration] = []

        for assertion in self {
            let scopedPaths = assertion.paths.isEmpty ? defaultPaths : assertion.paths

            switch (assertion.expectation, assertion.predicate) {
            case (.does, .declare(let names)):
                guard !names.isEmpty else { continue }
                publicDeclarationRules.append(
                    PublicDeclarationRuleConfiguration(
                        severity: assertion.severity,
                        paths: scopedPaths,
                        requiredNames: names
                    )
                )
            case (.doesNot, .declare(let names)):
                guard !names.isEmpty else { continue }
                publicDeclarationRules.append(
                    PublicDeclarationRuleConfiguration(
                        severity: assertion.severity,
                        paths: scopedPaths,
                        disallowedNames: names
                    )
                )
            case (.does, .containSyntax(let kinds)):
                guard !kinds.isEmpty else { continue }
                syntaxKindRules.append(
                    SyntaxKindRuleConfiguration(
                        severity: assertion.severity,
                        paths: scopedPaths,
                        requiredKinds: kinds
                    )
                )
            case (.doesNot, .containSyntax(let kinds)):
                guard !kinds.isEmpty else { continue }
                syntaxKindRules.append(
                    SyntaxKindRuleConfiguration(
                        severity: assertion.severity,
                        paths: scopedPaths,
                        disallowedKinds: kinds
                    )
                )
            case (.does, .containSyntaxNode(let matchers)):
                guard !matchers.isEmpty else { continue }
                syntaxNodeRules.append(
                    SyntaxNodeRuleConfiguration(
                        severity: assertion.severity,
                        paths: scopedPaths,
                        requiredNodes: matchers
                    )
                )
            case (.doesNot, .containSyntaxNode(let matchers)):
                guard !matchers.isEmpty else { continue }
                syntaxNodeRules.append(
                    SyntaxNodeRuleConfiguration(
                        severity: assertion.severity,
                        paths: scopedPaths,
                        disallowedNodes: matchers
                    )
                )
            }
        }

        return RuleConfiguration(
            syntaxKindRules: syntaxKindRules,
            syntaxNodeRules: syntaxNodeRules,
            publicDeclarationRules: publicDeclarationRules
        )
    }
}
public extension ComponentID {
    static let core = knownComponentID("core")
    static let cli = knownComponentID("cli")
    static let app = knownComponentID("app")
    static let ui = knownComponentID("ui")
    static let tests = knownComponentID("tests")
}

private func knownComponentID(_ rawValue: String) -> ComponentID {
    guard let id = try? ComponentID(rawValue) else {
        preconditionFailure("Invalid built-in component id: \(rawValue)")
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
