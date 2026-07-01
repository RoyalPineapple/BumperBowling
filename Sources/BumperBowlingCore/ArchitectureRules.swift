import Foundation

public struct ArchitectureRules: Equatable, Sendable {
    public let includedPaths: Set<RelativePathPrefix>
    public let excludedPaths: Set<RelativePathPrefix>
    public let subsystems: [SubsystemRule]
    public let subsystemByID: [SubsystemID: SubsystemRule]
    public let subsystemByModule: [ModuleName: SubsystemID]
    public let forbiddenImports: Set<ModuleName>
    public let ruleConfiguration: RuleConfiguration

    public init(configuration: ArchitectureConfiguration) throws {
        self.includedPaths = Set(try configuration.includedPaths.map(RelativePathPrefix.init))
        self.excludedPaths = Set(try configuration.excludedPaths.map(RelativePathPrefix.init))

        var subsystems: [SubsystemRule] = []
        var subsystemByID: [SubsystemID: SubsystemRule] = [:]
        var subsystemByModule: [ModuleName: SubsystemID] = [:]
        var ownedPaths: [RelativePathPrefix: SubsystemID] = [:]

        for subsystemConfiguration in configuration.subsystems {
            let subsystem = try SubsystemRule(configuration: subsystemConfiguration)

            guard subsystemByID[subsystem.id] == nil else {
                throw ConfigurationError.duplicateSubsystem(subsystem.id.rawValue)
            }

            for module in subsystem.modules {
                guard subsystemByModule[module] == nil else {
                    throw ConfigurationError.duplicateModule(module.rawValue)
                }
                subsystemByModule[module] = subsystem.id
            }

            for path in subsystem.paths {
                guard ownedPaths[path] == nil else {
                    throw ConfigurationError.duplicatePath(path.rawValue)
                }
                ownedPaths[path] = subsystem.id
            }

            subsystems.append(subsystem)
            subsystemByID[subsystem.id] = subsystem
        }

        let ids = Set(subsystems.map(\.id))
        for subsystem in subsystems {
            for dependency in subsystem.allowedDependencies.union(subsystem.forbiddenDependencies) where !ids.contains(dependency) {
                throw ConfigurationError.unknownDependency(subsystem.id.rawValue, dependency.rawValue)
            }
        }

        self.subsystems = subsystems
        self.subsystemByID = subsystemByID
        self.subsystemByModule = subsystemByModule
        self.forbiddenImports = Set(try configuration.rules.forbiddenImports.values.map(ModuleName.init))
        self.ruleConfiguration = configuration.rules
    }

    public func subsystem(containing relativePath: RelativeFilePath) -> SubsystemRule? {
        subsystems.first { subsystem in
            subsystem.paths.contains { $0.contains(relativePath) }
        }
    }

    public func includes(_ relativePath: RelativeFilePath) -> Bool {
        let included = includedPaths.isEmpty || includedPaths.contains { $0.contains(relativePath) }
        let excluded = excludedPaths.contains { $0.contains(relativePath) }
        return included && !excluded
    }
}

public struct SubsystemRule: Equatable, Sendable {
    public let id: SubsystemID
    public let modules: Set<ModuleName>
    public let paths: Set<RelativePathPrefix>
    public let allowedDependencies: Set<SubsystemID>
    public let forbiddenDependencies: Set<SubsystemID>

    init(configuration: SubsystemConfiguration) throws {
        let id = try SubsystemID(configuration.name)
        let configuredModules = try configuration.modules.map(ModuleName.init)
        let modules = Set(configuredModules + [try ModuleName(configuration.name)])

        self.id = id
        self.modules = modules
        self.paths = Set(try configuration.paths.map(RelativePathPrefix.init))
        self.allowedDependencies = Set(try configuration.mayDependOn.map(SubsystemID.init))
        self.forbiddenDependencies = Set(try configuration.mustNotDependOn.map(SubsystemID.init))

        guard !paths.isEmpty else {
            throw ConfigurationError.emptySubsystemPaths(id.rawValue)
        }
    }
}

public struct SubsystemID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            throw ConfigurationError.emptySubsystemName
        }
        self.rawValue = normalized
    }

    public var description: String {
        rawValue
    }
}

public struct ModuleName: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ConfigurationError.emptyModuleName
        }
        self.rawValue = normalized
    }

    public var description: String {
        rawValue
    }
}

public struct RelativeFilePath: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n\t"))
        guard !normalized.isEmpty else {
            throw ConfigurationError.emptyPath
        }
        self.rawValue = normalized
    }

    public var description: String {
        rawValue
    }
}

public struct RelativePathPrefix: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n\t"))
        guard !normalized.isEmpty else {
            throw ConfigurationError.emptyPath
        }
        self.rawValue = normalized
    }

    public func contains(_ relativePath: RelativeFilePath) -> Bool {
        relativePath.rawValue == rawValue || relativePath.rawValue.hasPrefix(rawValue + "/")
    }

    public var description: String {
        rawValue
    }
}

public enum ConfigurationError: Error, Equatable, CustomStringConvertible, Sendable {
    case emptySubsystemName
    case emptyModuleName
    case emptyPath
    case emptyDeclarationName
    case emptyAttributeName
    case emptyTypeName
    case emptySubsystemPaths(String)
    case duplicateSubsystem(String)
    case duplicateModule(String)
    case duplicatePath(String)
    case unknownDependency(String, String)

    public var description: String {
        switch self {
        case .emptySubsystemName:
            "Subsystem names cannot be empty."
        case .emptyModuleName:
            "Module names cannot be empty."
        case .emptyPath:
            "Subsystem paths cannot be empty."
        case .emptyDeclarationName:
            "Declaration names cannot be empty."
        case .emptyAttributeName:
            "Attribute names cannot be empty."
        case .emptyTypeName:
            "Type names cannot be empty."
        case .emptySubsystemPaths(let subsystem):
            "Subsystem \(subsystem) must own at least one path."
        case .duplicateSubsystem(let subsystem):
            "Duplicate subsystem: \(subsystem)."
        case .duplicateModule(let module):
            "Duplicate module alias: \(module)."
        case .duplicatePath(let path):
            "Duplicate subsystem path: \(path)."
        case .unknownDependency(let subsystem, let dependency):
            "Subsystem \(subsystem) references unknown dependency \(dependency)."
        }
    }
}
