import Foundation

public struct ArchitectureConfiguration: Equatable, Sendable {
    public let includedPaths: [String]
    public let excludedPaths: [String]
    public let subsystems: [SubsystemConfiguration]
    public let rules: RuleConfiguration

    public init(
        includedPaths: [String] = ["Sources"],
        excludedPaths: [String] = [".build", "DerivedData"],
        subsystems: [SubsystemConfiguration],
        rules: RuleConfiguration = RuleConfiguration()
    ) {
        self.includedPaths = includedPaths
        self.excludedPaths = excludedPaths
        self.subsystems = subsystems
        self.rules = rules
    }

    public static let bumperBowling = ArchitectureConfiguration(
        includedPaths: ["Sources"],
        excludedPaths: [".build", "DerivedData"],
        subsystems: [
            SubsystemConfiguration(
                name: "core",
                modules: ["BumperBowlingCore"],
                paths: ["Sources/BumperBowlingCore"],
                mayDependOn: []
            ),
            SubsystemConfiguration(
                name: "cli",
                modules: ["BumperBowling"],
                paths: ["Sources/BumperBowling"],
                mayDependOn: ["core"]
            ),
        ],
        rules: RuleConfiguration(
            forbiddenImports: [
                RuleSetting(
                    severity: .error,
                    values: ["XCTest", "Testing"],
                    paths: ["Sources/BumperBowlingCore"]
                ),
                RuleSetting(
                    severity: .error,
                    values: ["XCTest", "Testing"],
                    paths: ["Sources/BumperBowling"]
                ),
            ],
            subsystemBoundary: .error,
            duplicateOwnership: .error,
            dependencyCycle: .error,
            domainModels: DomainModelRuleConfiguration(
                severity: .warning,
                paths: ["Sources/BumperBowlingCore"],
                disallowances: [.any, .broadExistential, .storedVar, .rawStringIdentity]
            ),
            enumStateMachine: PathRuleConfiguration(
                severity: .error,
                paths: ["Sources/BumperBowlingCore/SwiftFileParser.swift"]
            )
        )
    )
}

public struct SubsystemConfiguration: Equatable, Sendable {
    public let name: String
    public let modules: [String]
    public let paths: [String]
    public let mayDependOn: [String]
    public let mustNotDependOn: [String]

    public init(
        name: String,
        modules: [String] = [],
        paths: [String],
        mayDependOn: [String] = [],
        mustNotDependOn: [String] = []
    ) {
        self.name = name
        self.modules = modules
        self.paths = paths
        self.mayDependOn = mayDependOn
        self.mustNotDependOn = mustNotDependOn
    }
}

public struct RuleConfiguration: Equatable, Sendable {
    public let forbiddenImports: [RuleSetting]
    public let subsystemBoundary: Severity
    public let duplicateOwnership: Severity
    public let dependencyCycle: Severity
    public let domainModels: DomainModelRuleConfiguration
    public let enumStateMachine: PathRuleConfiguration

    public init(
        forbiddenImports: RuleSetting = RuleSetting(severity: .off, values: []),
        subsystemBoundary: Severity = .off,
        duplicateOwnership: Severity = .off,
        dependencyCycle: Severity = .off,
        domainModels: DomainModelRuleConfiguration = DomainModelRuleConfiguration(),
        enumStateMachine: PathRuleConfiguration = PathRuleConfiguration()
    ) {
        self.forbiddenImports = forbiddenImports.isConfigured ? [forbiddenImports] : []
        self.subsystemBoundary = subsystemBoundary
        self.duplicateOwnership = duplicateOwnership
        self.dependencyCycle = dependencyCycle
        self.domainModels = domainModels
        self.enumStateMachine = enumStateMachine
    }

    public init(
        forbiddenImports: [RuleSetting],
        subsystemBoundary: Severity = .off,
        duplicateOwnership: Severity = .off,
        dependencyCycle: Severity = .off,
        domainModels: DomainModelRuleConfiguration = DomainModelRuleConfiguration(),
        enumStateMachine: PathRuleConfiguration = PathRuleConfiguration()
    ) {
        self.forbiddenImports = forbiddenImports.filter(\.isConfigured)
        self.subsystemBoundary = subsystemBoundary
        self.duplicateOwnership = duplicateOwnership
        self.dependencyCycle = dependencyCycle
        self.domainModels = domainModels
        self.enumStateMachine = enumStateMachine
    }
}

public struct RuleSetting: Equatable, Sendable {
    public let severity: Severity
    public let values: [String]
    public let paths: [String]

    public init(severity: Severity, values: [String], paths: [String] = []) {
        self.severity = severity
        self.values = values
        self.paths = paths
    }

    var isConfigured: Bool {
        severity != .off || !values.isEmpty || !paths.isEmpty
    }
}

public struct DomainModelRuleConfiguration: Equatable, Sendable {
    public let severity: Severity
    public let paths: [String]
    public let disallowances: Set<DomainModelDisallowance>
    public let imperativeConstructs: Set<ImperativeConstruct>

    public init(
        severity: Severity = .off,
        paths: [String] = [],
        disallowances: Set<DomainModelDisallowance> = [],
        imperativeConstructs: Set<ImperativeConstruct> = []
    ) {
        self.severity = severity
        self.paths = paths
        self.disallowances = disallowances
        self.imperativeConstructs = imperativeConstructs
    }
}

public struct PathRuleConfiguration: Equatable, Sendable {
    public let severity: Severity
    public let paths: [String]

    public init(severity: Severity = .off, paths: [String] = []) {
        self.severity = severity
        self.paths = paths
    }
}

public enum DomainModelDisallowance: String, Equatable, Hashable, Sendable {
    case any
    case broadExistential
    case storedVar
    case rawStringIdentity
    case imperativeConstructs
}

extension Severity {
    func merging(_ other: Severity) -> Severity {
        switch (self, other) {
        case (.error, _), (_, .error):
            .error
        case (.warning, _), (_, .warning):
            .warning
        case (.note, _), (_, .note):
            .note
        case (.off, .off):
            .off
        }
    }
}

public enum ConfigurationLoader {
    public static let fileName = "BumperBowling.swift"

    public static func load(from root: URL) throws -> ArchitectureConfiguration {
        ArchitectureConfiguration.bumperBowling
    }

    public static func writeSample(to root: URL) throws {
        let url = root.appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw BumperError.configurationAlreadyExists(url.path)
        }

        try Self.sampleDSL.write(to: url, atomically: true, encoding: .utf8)
    }

    private static let sampleDSL = """
    import BumperBowlingCore

    // Bumper Bowling 0.0 exposes the Swift DSL as the typed configuration API.
    // The CLI still uses its built-in repository config until config loading lands.
    let configuration = BumperConfiguration {
        Defaults(.strict)

        Included {
            "Sources"
        }

        Excluded {
            ".build"
            "DerivedData"
        }

        Architecture {
            Component(.core) {
                Owns("Sources/BumperBowlingCore")
                Modules("BumperBowlingCore")
                MayUse(.foundation)
                Requires(.explicitDomainSurfaces, .typedIdentity, .immutableStoredState, severity: .warning)
                RequiresScoped(.enumStateMachine, "Sources/BumperBowlingCore/SwiftFileParser.swift", severity: .error)
            }

            Component(.cli) {
                Owns("Sources/BumperBowling")
                Modules("BumperBowling")
                MayDependOn(.core)
                MayUse(.foundation)
            }
        }

        Assertions {
            DependencyBoundaries(.error)
            SingleOwner(.error)
            AcyclicDependencies(.error)
        }
    }
    """
}
