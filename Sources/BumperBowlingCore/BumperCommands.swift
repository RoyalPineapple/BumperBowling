import Foundation

public enum BumperCommands {
    public static func initialize(at root: URL) throws {
        try ConfigurationLoader.writeSample(to: root)
        print("Created sample \(ConfigurationLoader.fileName)")
        print("Run `bumper lint \(root.path)` to validate this repository.")
    }

    public static func scan(root: URL) async throws -> String {
        try ConfigurationLoader.runStringCommand(.scan, root: root)
    }

    public static func scan(root: URL, configuration: ArchitectureConfiguration) async throws -> String {
        let model = try await RepositoryScanner(configuration: configuration).scan(root: root)

        var lines: [String] = []
        lines.append("# Architecture Scan")
        lines.append("")
        lines.append("Files: \(model.files.count)")
        let subsystems = Set(model.files.map(\.subsystem.rawValue)).sorted().joined(separator: ", ")
        lines.append("Subsystems: \(subsystems)")
        lines.append("")
        lines.append("## Dependencies")

        for edge in model.dependencyEdges.sorted(by: { "\($0.sourceSubsystem.rawValue).\($0.importedModule.rawValue)" < "\($1.sourceSubsystem.rawValue).\($1.importedModule.rawValue)" }) {
            lines.append("- \(edge.sourceSubsystem) imports \(edge.importedModule)")
        }

        return lines.joined(separator: "\n")
    }

    public static func snapshot(root: URL) throws -> String {
        try ConfigurationLoader.runStringCommand(.snapshot, root: root)
    }

    public static func snapshot(configuration: ArchitectureConfiguration) throws -> String {
        return try ArchitectureSnapshot(configuration: configuration).render()
    }

    public static func lint(root: URL) async throws -> LintReport {
        try ConfigurationLoader.runLint(root: root)
    }

    public static func lint(root: URL, configuration: ArchitectureConfiguration) async throws -> LintReport {
        let rules = try ArchitectureRules(configuration: configuration)
        let model = try await RepositoryScanner(rules: rules).scan(root: root)
        return ArchitectureLinter(rules: rules).lint(model)
    }

    public static func explain(path: URL, root: URL) async throws -> String {
        try ConfigurationLoader.runStringCommand(.explain(path), root: root)
    }

    public static func explain(path: URL, root: URL, configuration: ArchitectureConfiguration) async throws -> String {
        let scanner = try RepositoryScanner(configuration: configuration)
        let file = try await scanner.scanFile(path, root: root)

        var lines: [String] = []
        lines.append("# \(file.path.rawValue)")
        lines.append("")
        lines.append("Subsystem: \(file.subsystem)")
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
