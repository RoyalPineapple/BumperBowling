import Foundation

public enum BumperCommands {
    public static func initialize(at root: URL) throws {
        try ConfigurationLoader.writeSample(to: root)
        print("Created sample \(ConfigurationLoader.fileName)")
        print("Run `bumper lint \(root.path)` to validate this repository.")
    }

    public static func scan(root: URL) async throws -> String {
        try await scan(root: root, configuration: ConfigurationLoader.loadConfiguration(root: root))
    }

    public static func scan(root: URL, configuration: ArchitectureConfiguration) async throws -> String {
        let model = try await RepositoryScanner(configuration: configuration).scan(root: root)

        var lines: [String] = []
        lines.append("# Architecture Scan")
        lines.append("")
        lines.append("Files: \(model.files.count)")
        let components = Set(model.files.map(\.component.rawValue)).sorted().joined(separator: ", ")
        lines.append("Components: \(components)")
        lines.append("")
        lines.append("## Dependencies")

        for edge in model.dependencyEdges.sorted(by: dependencyEdgeSortKey) {
            lines.append("- \(edge.sourceComponent) imports \(edge.importedModule)")
        }

        return lines.joined(separator: "\n")
    }

    public static func snapshot(root: URL) throws -> String {
        try snapshot(configuration: ConfigurationLoader.loadConfiguration(root: root))
    }

    public static func snapshot(configuration: ArchitectureConfiguration) throws -> String {
        return try ArchitectureSnapshot(configuration: configuration).render()
    }

    public static func lint(root: URL) async throws -> LintReport {
        try await lint(root: root, configuration: ConfigurationLoader.loadConfiguration(root: root))
    }

    public static func lint(root: URL, configuration: ArchitectureConfiguration) async throws -> LintReport {
        let rules = try ArchitectureRules(configuration: configuration)
        let model = try await RepositoryScanner(rules: rules).scan(root: root)
        return ArchitectureLinter(rules: rules).lint(model)
    }

    public static func checkConfiguration(root: URL) throws -> ConfigurationReport {
        do {
            let configuration = try ConfigurationLoader.loadConfiguration(root: root)
            _ = try ArchitectureRules(configuration: configuration)
            return ConfigurationReport(problem: nil)
        } catch {
            return ConfigurationReport(problem: String(describing: error))
        }
    }

    public static func explain(path: URL, root: URL) async throws -> String {
        try await explain(
            path: path,
            root: root,
            configuration: ConfigurationLoader.loadConfiguration(root: root)
        )
    }

    public static func explain(path: URL, root: URL, configuration: ArchitectureConfiguration) async throws -> String {
        let scanner = try RepositoryScanner(configuration: configuration)
        let file = try await scanner.scanFile(path, root: root)

        var lines: [String] = []
        lines.append("# \(file.path.rawValue)")
        lines.append("")
        lines.append("Component: \(file.component)")
        let imports = file.imports.map(\.rawValue).joined(separator: ", ")
        lines.append("Imports: \(imports.isEmpty ? "none" : imports)")
        lines.append("")
        lines.append("## Public API")

        if file.publicDeclarations.isEmpty {
            lines.append("None detected.")
        } else {
            for declaration in file.publicDeclarations {
                lines.append("- \(declaration.kind.rawValue) \(declaration.name.rawValue)")
            }
        }

        return lines.joined(separator: "\n")
    }

}

public struct ConfigurationReport: Equatable, Sendable {
    public let problem: String?

    public var isValid: Bool {
        problem == nil
    }

    public var summary: String {
        if let problem {
            return "The configuration is not valid: \(problem)"
        }
        return "The configuration is valid."
    }
}

private func dependencyEdgeSortKey(_ lhs: DependencyEdge, _ rhs: DependencyEdge) -> Bool {
    "\(lhs.sourceComponent.rawValue).\(lhs.importedModule.rawValue)"
        < "\(rhs.sourceComponent.rawValue).\(rhs.importedModule.rawValue)"
}
