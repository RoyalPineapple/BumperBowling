import Foundation
import SwiftSyntax

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
    public let declaredDependencyCycle: Severity
    public let storedProperties: StoredPropertyRuleConfiguration
    public let syntaxConstructs: SyntaxConstructRuleConfiguration
    public let syntaxKinds: SyntaxKindRuleConfiguration
    public let publicDeclarations: PublicDeclarationRuleConfiguration
    public let enumStateMachine: PathRuleConfiguration

    public init(
        forbiddenImports: RuleSetting = RuleSetting(severity: .off, values: []),
        subsystemBoundary: Severity = .off,
        duplicateOwnership: Severity = .off,
        declaredDependencyCycle: Severity = .off,
        storedProperties: StoredPropertyRuleConfiguration = StoredPropertyRuleConfiguration(),
        syntaxConstructs: SyntaxConstructRuleConfiguration = SyntaxConstructRuleConfiguration(),
        syntaxKinds: SyntaxKindRuleConfiguration = SyntaxKindRuleConfiguration(),
        publicDeclarations: PublicDeclarationRuleConfiguration = PublicDeclarationRuleConfiguration(),
        enumStateMachine: PathRuleConfiguration = PathRuleConfiguration()
    ) {
        self.forbiddenImports = forbiddenImports.isConfigured ? [forbiddenImports] : []
        self.subsystemBoundary = subsystemBoundary
        self.duplicateOwnership = duplicateOwnership
        self.declaredDependencyCycle = declaredDependencyCycle
        self.storedProperties = storedProperties
        self.syntaxConstructs = syntaxConstructs
        self.syntaxKinds = syntaxKinds
        self.publicDeclarations = publicDeclarations
        self.enumStateMachine = enumStateMachine
    }

    public init(
        forbiddenImports: [RuleSetting],
        subsystemBoundary: Severity = .off,
        duplicateOwnership: Severity = .off,
        declaredDependencyCycle: Severity = .off,
        storedProperties: StoredPropertyRuleConfiguration = StoredPropertyRuleConfiguration(),
        syntaxConstructs: SyntaxConstructRuleConfiguration = SyntaxConstructRuleConfiguration(),
        syntaxKinds: SyntaxKindRuleConfiguration = SyntaxKindRuleConfiguration(),
        publicDeclarations: PublicDeclarationRuleConfiguration = PublicDeclarationRuleConfiguration(),
        enumStateMachine: PathRuleConfiguration = PathRuleConfiguration()
    ) {
        self.forbiddenImports = forbiddenImports.filter(\.isConfigured)
        self.subsystemBoundary = subsystemBoundary
        self.duplicateOwnership = duplicateOwnership
        self.declaredDependencyCycle = declaredDependencyCycle
        self.storedProperties = storedProperties
        self.syntaxConstructs = syntaxConstructs
        self.syntaxKinds = syntaxKinds
        self.publicDeclarations = publicDeclarations
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

public struct StoredPropertyRuleConfiguration: Equatable, Sendable {
    public let severity: Severity
    public let paths: [String]
    public let disallowances: Set<StoredPropertyDisallowance>

    public init(
        severity: Severity = .off,
        paths: [String] = [],
        disallowances: Set<StoredPropertyDisallowance> = []
    ) {
        self.severity = severity
        self.paths = paths
        self.disallowances = disallowances
    }
}

public struct SyntaxConstructRuleConfiguration: Equatable, Sendable {
    public let severity: Severity
    public let paths: [String]
    public let excludedPaths: [String]
    public let disallowedConstructs: Set<ImperativeConstruct>

    public init(
        severity: Severity = .off,
        paths: [String] = [],
        excludedPaths: [String] = [],
        disallowedConstructs: Set<ImperativeConstruct> = []
    ) {
        self.severity = severity
        self.paths = paths
        self.excludedPaths = excludedPaths
        self.disallowedConstructs = disallowedConstructs
    }
}

public struct SyntaxKindRuleConfiguration: Equatable, Sendable {
    public let severity: Severity
    public let paths: [String]
    public let requiredKinds: Set<SyntaxKind>
    public let disallowedKinds: Set<SyntaxKind>

    public init(
        severity: Severity = .off,
        paths: [String] = [],
        requiredKinds: Set<SyntaxKind> = [],
        disallowedKinds: Set<SyntaxKind> = []
    ) {
        self.severity = severity
        self.paths = paths
        self.requiredKinds = requiredKinds
        self.disallowedKinds = disallowedKinds
    }
}

public struct PublicDeclarationRuleConfiguration: Equatable, Sendable {
    public let severity: Severity
    public let paths: [String]
    public let requiredNames: Set<StringMatcher>
    public let disallowedNames: Set<StringMatcher>

    public init(
        severity: Severity = .off,
        paths: [String] = [],
        requiredNames: Set<StringMatcher> = [],
        disallowedNames: Set<StringMatcher> = []
    ) {
        self.severity = severity
        self.paths = paths
        self.requiredNames = requiredNames
        self.disallowedNames = disallowedNames
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

public enum StoredPropertyDisallowance: String, Equatable, Hashable, Sendable {
    case any
    case broadExistential
    case storedProperty
    case storedVar
    case rawStringIdentity
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

    public static func writeSample(to root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw BumperError.configurationAlreadyExists(url.path)
        }

        try Self.sampleDSL.write(to: url, atomically: true, encoding: .utf8)
    }

    private static let sampleDSL = """
    import BumperBowlingCore

    // Bumper Bowling exposes this Swift DSL to both shipped interfaces:
    // - the CLI loads this file for shell hooks and CI jobs
    // - BumperBowlingTesting can use the same configuration value in tests
    let configuration = BumperConfiguration {
        Included {
            "Sources"
        }

        Excluded {
            ".build"
            "DerivedData"
        }

        Architecture {
            Component(.app) {
                Owns("Sources")
                Modules("App")
                MayUse(.foundation)
                Requires(
                    .explicitDomainSurfaces,
                    .typedIdentity,
                    .immutableStoredState,
                    severity: .warning
                )
            }
        }

        Assertions {
            DependencyBoundaries(.error)
            SingleOwner(.error)
            AcyclicDeclaredDependencies(.error)
        }
    }
    """
}
