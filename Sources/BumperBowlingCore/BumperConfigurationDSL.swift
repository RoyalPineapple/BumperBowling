import Foundation

public struct BumperConfiguration: Equatable, Sendable {
    public let architectureConfiguration: ArchitectureConfiguration

    public init(@BumperConfigurationBuilder _ content: () -> [BumperConfigurationElement]) {
        var includedPaths: [String] = ["Sources"]
        var excludedPaths: [String] = [".build", "DerivedData"]
        var subsystems: [SubsystemConfiguration] = []
        var rules = RuleConfiguration()

        for element in content() {
            switch element {
            case .defaults:
                continue
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
    case defaults(ConfigurationProfile)
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

public enum ConfigurationProfile: Equatable, Sendable {
    case standard
    case strict
}

public func Defaults(_ profile: ConfigurationProfile) -> BumperConfigurationElement {
    .defaults(profile)
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
    var usePolicies: [ComponentUsePolicy] = []
    var requirements: [ComponentRequirementSetting] = []
    var disallowances: [ImperativeDisallowanceSetting] = []

    for element in content() {
        switch element {
        case .owns(let values):
            paths.append(contentsOf: values)
        case .modules(let values):
            modules.append(contentsOf: values)
        case .mayDependOn(let values):
            dependencies.append(contentsOf: values.map(\.rawValue))
        case .usePolicy(let values):
            usePolicies.append(contentsOf: values)
        case .requires(let values):
            requirements.append(contentsOf: values)
        case .disallows(let values):
            disallowances.append(contentsOf: values)
        }
    }

    return ComponentConfiguration(
        subsystem: SubsystemConfiguration(
            name: id.rawValue,
            modules: modules,
            paths: paths,
            mayDependOn: dependencies
        ),
        derivedRules: requirements.derivedRules(defaultPaths: paths)
            .merging(usePolicies.derivedRules(defaultPaths: paths))
            .merging(disallowances.derivedRules(defaultPaths: paths))
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
    case usePolicy([ComponentUsePolicy])
    case requires([ComponentRequirementSetting])
    case disallows([ImperativeDisallowanceSetting])
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
    case fileSystem
    case clock
    case randomness
    case taskSpawning
    case mainActor
    case testing
    case unsafeRuntime

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
        case .fileSystem, .clock, .randomness, .taskSpawning, .mainActor, .unsafeRuntime:
            []
        }
    }
}

public enum ComponentRequirement: Equatable, Sendable {
    case explicitDomainSurfaces
    case typedIdentity
    case immutableStoredState
    case enumStateMachine
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
}

public func Owns(_ paths: String...) -> DSLPathList {
    DSLPathList(values: paths)
}

public func MayDependOn(_ dependencies: SubsystemID...) -> ComponentElement {
    .mayDependOn(dependencies)
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

public func AcyclicDependencies(_ severity: Severity) -> RuleConfiguration {
    RuleConfiguration(dependencyCycle: severity)
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
        var domainSeverity = Severity.off
        var domainDisallowances = Set<DomainModelDisallowance>()
        var domainPaths: [String] = []
        var enumStateMachine = PathRuleConfiguration()

        for setting in self {
            let scopedPaths = setting.paths.isEmpty ? defaultPaths : setting.paths

            switch setting.requirement {
            case .explicitDomainSurfaces:
                domainSeverity = domainSeverity.merging(setting.severity)
                domainPaths.append(contentsOf: scopedPaths)
                domainDisallowances.formUnion([.any, .broadExistential])
            case .typedIdentity:
                domainSeverity = domainSeverity.merging(setting.severity)
                domainPaths.append(contentsOf: scopedPaths)
                domainDisallowances.insert(.rawStringIdentity)
            case .immutableStoredState:
                domainSeverity = domainSeverity.merging(setting.severity)
                domainPaths.append(contentsOf: scopedPaths)
                domainDisallowances.insert(.storedVar)
            case .enumStateMachine:
                enumStateMachine = PathRuleConfiguration(
                    severity: enumStateMachine.severity.merging(setting.severity),
                    paths: enumStateMachine.paths + scopedPaths
                )
            }
        }

        return RuleConfiguration(
            domainModels: DomainModelRuleConfiguration(
                severity: domainSeverity,
                paths: Swift.Array(Set(domainPaths)).sorted(),
                disallowances: domainDisallowances
            ),
            enumStateMachine: enumStateMachine
        )
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
        var constructs = Set<ImperativeConstruct>()

        for setting in self {
            severity = severity.merging(setting.severity)
            paths.append(contentsOf: setting.paths.isEmpty ? defaultPaths : setting.paths)
            constructs.formUnion(setting.constructs)
        }

        guard !constructs.isEmpty else {
            return RuleConfiguration()
        }

        return RuleConfiguration(
            domainModels: DomainModelRuleConfiguration(
                severity: severity,
                paths: Swift.Array(Set(paths)).sorted(),
                disallowances: [.imperativeConstructs],
                imperativeConstructs: constructs
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
            dependencyCycle: other.dependencyCycle.isConfigured ? other.dependencyCycle : dependencyCycle,
            domainModels: domainModels.merging(other.domainModels),
            enumStateMachine: enumStateMachine.merging(other.enumStateMachine)
        )
    }
}

private extension DomainModelRuleConfiguration {
    func merging(_ other: DomainModelRuleConfiguration) -> DomainModelRuleConfiguration {
        DomainModelRuleConfiguration(
            severity: severity.merging(other.severity),
            paths: Array(Set(paths + other.paths)).sorted(),
            disallowances: disallowances.union(other.disallowances),
            imperativeConstructs: imperativeConstructs.union(other.imperativeConstructs)
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

private extension DomainModelRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty || !disallowances.isEmpty || !imperativeConstructs.isEmpty
    }
}

private extension PathRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty
    }
}

public extension SubsystemID {
    static let core = try! SubsystemID("core")
    static let cli = try! SubsystemID("cli")
    static let app = try! SubsystemID("app")
    static let ui = try! SubsystemID("ui")
    static let tests = try! SubsystemID("tests")
}
