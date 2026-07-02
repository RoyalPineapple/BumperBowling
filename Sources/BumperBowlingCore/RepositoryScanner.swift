import Foundation

public struct RepositoryScanner: Sendable {
    private let rules: ArchitectureRules
    private let parser: SwiftFileParser

    public init(
        configuration: ArchitectureConfiguration,
        parser: SwiftFileParser = SwiftFileParser()
    ) throws {
        self.rules = try ArchitectureRules(configuration: configuration)
        self.parser = parser
    }

    public init(
        rules: ArchitectureRules,
        parser: SwiftFileParser = SwiftFileParser()
    ) {
        self.rules = rules
        self.parser = parser
    }

    public func scan(root: URL) async throws -> RepositoryFacts {
        let inputs = sourceFileInputs(in: root)

        let files = try await withThrowingTaskGroup(of: SourceFileFacts.self) { group in
            for input in inputs {
                let parser = parser
                group.addTask {
                    try parser.parseFile(
                        at: input.url,
                        relativePath: input.relativePath,
                        subsystem: input.subsystem
                    )
                }
            }

            var files: [SourceFileFacts] = []
            for try await file in group {
                files.append(file)
            }
            return files
        }

        return RepositoryFacts(files: files.sorted(by: { $0.path.rawValue < $1.path.rawValue }))
    }

    private func sourceFileInputs(in root: URL) -> [SwiftSourceFileInput] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var inputs: [SwiftSourceFileInput] = []

        for case let url as URL in enumerator {
            let relativePath = Self.relativePath(for: url, root: root)
            if shouldSkip(relativePath) {
                if url.hasDirectoryPath {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard let typedRelativePath = try? RelativeFilePath(relativePath),
                  rules.includes(typedRelativePath),
                  let subsystem = rules.subsystem(containing: typedRelativePath),
                  isSwiftFile(typedRelativePath) else {
                continue
            }

            inputs.append(
                SwiftSourceFileInput(
                    url: url,
                    relativePath: typedRelativePath,
                    subsystem: subsystem.id
                )
            )
        }

        return inputs
    }

    public func scanFile(_ url: URL, root: URL) async throws -> SourceFileFacts {
        let relativePath = Self.relativePath(for: url, root: root)
        let typedRelativePath = try RelativeFilePath(relativePath)
        guard let subsystem = rules.subsystem(containing: typedRelativePath) else {
            throw BumperError.noSubsystemForFile(relativePath)
        }

        guard isSwiftFile(typedRelativePath) else {
            throw BumperError.unsupportedLanguage(relativePath)
        }

        return try parser.parseFile(
            at: url,
            relativePath: typedRelativePath,
            subsystem: subsystem.id
        )
    }

    private func isSwiftFile(_ path: RelativeFilePath) -> Bool {
        path.rawValue.hasSuffix(".swift")
    }

    private func shouldSkip(_ relativePath: String) -> Bool {
        relativePath.hasPrefix(".build/")
            || relativePath.hasPrefix(".git/")
            || relativePath.hasPrefix("DerivedData/")
    }

    private static func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path

        if filePath == rootPath {
            return ""
        }

        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if filePath.hasPrefix(prefix) {
            return String(filePath.dropFirst(prefix.count))
        }

        return filePath
    }
}

private struct SwiftSourceFileInput: Sendable {
    let url: URL
    let relativePath: RelativeFilePath
    let subsystem: SubsystemID
}
