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
            case .included(let paths):
                includedPaths = paths
            case .excluded(let paths):
                excludedPaths = paths
            case .subsystems(let configuredSubsystems):
                subsystems = configuredSubsystems
            case .rules(let configuredRules):
                rules = rules.merging(configuredRules)
            case .optInRules(let configuredRules):
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
    case included([String])
    case excluded([String])
    case subsystems([SubsystemConfiguration])
    case rules(RuleConfiguration)
    case optInRules(RuleConfiguration)
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

public func Subsystems(@SubsystemsBuilder _ content: () -> [SubsystemConfiguration]) -> BumperConfigurationElement {
    .subsystems(content())
}

public func Rules(@RulesBuilder _ content: () -> [RuleConfiguration]) -> BumperConfigurationElement {
    .rules(content().combined())
}

public func OptInRules(@RulesBuilder _ content: () -> [RuleConfiguration]) -> BumperConfigurationElement {
    .optInRules(content().combined())
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

@resultBuilder
public enum SubsystemsBuilder {
    public static func buildBlock(_ components: SubsystemConfiguration...) -> [SubsystemConfiguration] {
        components
    }
}

public func Subsystem(
    _ id: SubsystemID,
    @SubsystemBuilder _ content: () -> [SubsystemElement]
) -> SubsystemConfiguration {
    var paths: [String] = []
    var modules: [String] = []
    var dependencies: [String] = []
    var forbiddenDependencies: [String] = []

    for element in content() {
        switch element {
        case .paths(let values):
            paths.append(contentsOf: values)
        case .modules(let values):
            modules.append(contentsOf: values)
        case .dependencies(let values):
            dependencies.append(contentsOf: values.map(\.rawValue))
        case .forbiddenDependencies(let values):
            forbiddenDependencies.append(contentsOf: values.map(\.rawValue))
        }
    }

    return SubsystemConfiguration(
        name: id.rawValue,
        modules: modules,
        paths: paths,
        mayDependOn: dependencies,
        mustNotDependOn: forbiddenDependencies
    )
}

@resultBuilder
public enum SubsystemBuilder {
    public static func buildBlock(_ components: SubsystemElement...) -> [SubsystemElement] {
        components
    }

    public static func buildExpression(_ expression: DSLPathList) -> SubsystemElement {
        .paths(expression.values)
    }

    public static func buildExpression(_ expression: DSLModuleList) -> SubsystemElement {
        .modules(expression.values)
    }

    public static func buildExpression(_ expression: SubsystemElement) -> SubsystemElement {
        expression
    }
}

public enum SubsystemElement: Equatable, Sendable {
    case paths([String])
    case modules([String])
    case dependencies([SubsystemID])
    case forbiddenDependencies([SubsystemID])
}

public func Dependencies(_ dependencies: SubsystemID...) -> SubsystemElement {
    .dependencies(dependencies)
}

public func ForbiddenDependencies(_ dependencies: SubsystemID...) -> SubsystemElement {
    .forbiddenDependencies(dependencies)
}

@resultBuilder
public enum RulesBuilder {
    public static func buildBlock(_ components: RuleConfiguration...) -> [RuleConfiguration] {
        components
    }
}

public func ForbiddenImport(
    _ severity: Severity,
    @ForbiddenImportBuilder _ content: () -> [ForbiddenImportElement]
) -> RuleConfiguration {
    let modules = content().flatMap { element in
        switch element {
        case .modules(let values):
            values
        case .appliesTo:
            [String]()
        }
    }
    return RuleConfiguration(forbiddenImports: RuleSetting(severity: severity, values: modules))
}

@resultBuilder
public enum ForbiddenImportBuilder {
    public static func buildBlock(_ components: ForbiddenImportElement...) -> [ForbiddenImportElement] {
        components
    }

    public static func buildExpression(_ expression: DSLModuleList) -> ForbiddenImportElement {
        .modules(expression.values)
    }

    public static func buildExpression(_ expression: ForbiddenImportElement) -> ForbiddenImportElement {
        expression
    }
}

public enum ForbiddenImportElement: Equatable, Sendable {
    case modules([String])
    case appliesTo(ImportRuleScope)
}

public enum ImportRuleScope: Equatable, Sendable {
    case production
}

public func AppliesTo(_ scope: ImportRuleScope) -> ForbiddenImportElement {
    .appliesTo(scope)
}

public func SubsystemBoundary(_ severity: Severity) -> RuleConfiguration {
    RuleConfiguration(subsystemBoundary: severity)
}

public func DuplicateOwnership(_ severity: Severity) -> RuleConfiguration {
    RuleConfiguration(duplicateOwnership: severity)
}

public func DependencyCycle(_ severity: Severity) -> RuleConfiguration {
    RuleConfiguration(dependencyCycle: severity)
}

public func DomainModels(
    _ severity: Severity,
    @DomainModelsBuilder _ content: () -> [DomainModelElement]
) -> RuleConfiguration {
    var paths: [String] = []
    var disallowances = Set<DomainModelDisallowance>()

    for element in content() {
        switch element {
        case .paths(let values):
            paths.append(contentsOf: values)
        case .disallow(let value):
            disallowances.insert(value)
        }
    }

    return RuleConfiguration(
        domainModels: DomainModelRuleConfiguration(
            severity: severity,
            paths: paths,
            disallowances: disallowances
        )
    )
}

@resultBuilder
public enum DomainModelsBuilder {
    public static func buildBlock(_ components: DomainModelElement...) -> [DomainModelElement] {
        components
    }

    public static func buildExpression(_ expression: DSLPathList) -> DomainModelElement {
        .paths(expression.values)
    }

    public static func buildExpression(_ expression: DomainModelElement) -> DomainModelElement {
        expression
    }
}

public enum DomainModelElement: Equatable, Sendable {
    case paths([String])
    case disallow(DomainModelDisallowance)
}

public func Disallow(_ disallowance: DomainModelDisallowance) -> DomainModelElement {
    .disallow(disallowance)
}

public func EnumStateMachine(
    _ severity: Severity,
    @PathRuleBuilder _ content: () -> [PathRuleElement]
) -> RuleConfiguration {
    RuleConfiguration(
        enumStateMachine: PathRuleConfiguration(
            severity: severity,
            paths: content().flatMap(\.paths)
        )
    )
}

@resultBuilder
public enum PathRuleBuilder {
    public static func buildBlock(_ components: PathRuleElement...) -> [PathRuleElement] {
        components
    }

    public static func buildExpression(_ expression: DSLPathList) -> PathRuleElement {
        PathRuleElement(paths: expression.values)
    }
}

public struct PathRuleElement: Equatable, Sendable {
    public let paths: [String]
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

private extension RuleConfiguration {
    func merging(_ other: RuleConfiguration) -> RuleConfiguration {
        RuleConfiguration(
            forbiddenImports: other.forbiddenImports.isConfigured ? other.forbiddenImports : forbiddenImports,
            subsystemBoundary: other.subsystemBoundary.isConfigured ? other.subsystemBoundary : subsystemBoundary,
            duplicateOwnership: other.duplicateOwnership.isConfigured ? other.duplicateOwnership : duplicateOwnership,
            dependencyCycle: other.dependencyCycle.isConfigured ? other.dependencyCycle : dependencyCycle,
            domainModels: other.domainModels.isConfigured ? other.domainModels : domainModels,
            enumStateMachine: other.enumStateMachine.isConfigured ? other.enumStateMachine : enumStateMachine
        )
    }
}

private extension RuleSetting {
    var isConfigured: Bool {
        severity != .off || !values.isEmpty
    }
}

private extension Severity {
    var isConfigured: Bool {
        self != .off
    }
}

private extension DomainModelRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty || !disallowances.isEmpty
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
