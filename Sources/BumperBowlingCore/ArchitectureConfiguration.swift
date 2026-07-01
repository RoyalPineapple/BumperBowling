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
            forbiddenImports: RuleSetting(
                severity: .error,
                values: ["XCTest"]
            ),
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
    public let forbiddenImports: RuleSetting
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
        self.forbiddenImports = forbiddenImports
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

    public init(severity: Severity, values: [String]) {
        self.severity = severity
        self.values = values
    }
}

public struct DomainModelRuleConfiguration: Equatable, Sendable {
    public let severity: Severity
    public let paths: [String]
    public let disallowances: Set<DomainModelDisallowance>

    public init(
        severity: Severity = .off,
        paths: [String] = [],
        disallowances: Set<DomainModelDisallowance> = []
    ) {
        self.severity = severity
        self.paths = paths
        self.disallowances = disallowances
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

    let configuration = BumperConfiguration {
        Defaults(.strict)

        Included {
            "Sources"
        }

        Excluded {
            ".build"
            "DerivedData"
        }

        Subsystems {
            Subsystem(.core) {
                Paths("Sources/BumperBowlingCore")
                Modules("BumperBowlingCore")
            }

            Subsystem(.cli) {
                Paths("Sources/BumperBowling")
                Modules("BumperBowling")
                Dependencies(.core)
            }
        }

        Rules {
            ForbiddenImport(.error) {
                Modules("XCTest", "Testing")
                AppliesTo(.production)
            }

            SubsystemBoundary(.error)
            DuplicateOwnership(.error)
            DependencyCycle(.error)

            DomainModels(.warning) {
                Paths("Sources/BumperBowlingCore")
                Disallow(.any)
                Disallow(.broadExistential)
                Disallow(.storedVar)
                Disallow(.rawStringIdentity)
            }
        }

        OptInRules {
            EnumStateMachine(.error) {
                Paths("Sources/**/*Parser.swift")
            }
        }
    }
    """
}
