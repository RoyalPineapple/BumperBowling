import SwiftSyntax

public struct ComponentConfiguration: Equatable, Sendable {
    public let subsystem: SubsystemConfiguration
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
    _ id: SubsystemID,
    @ComponentBuilder _ content: () -> [ComponentElement]
) -> ComponentConfiguration {
    makeComponentConfiguration(id, elements: content())
}

func makeComponentConfiguration(
    _ id: SubsystemID,
    elements: [ComponentElement]
) -> ComponentConfiguration {
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
        var storedPropertySeverity = Severity.off
        var storedPropertyDisallowances = Set<StoredPropertyDisallowance>()
        var storedPropertyPaths: [String] = []
        var storedPropertyExcludedPaths: [String] = []
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
                storedPropertyExcludedPaths.append(contentsOf: setting.excludedPaths)
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
                excludedPaths: Swift.Array(Set(storedPropertyExcludedPaths)).sorted(),
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
