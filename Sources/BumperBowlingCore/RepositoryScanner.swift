import Foundation

public struct RepositoryScanner: Sendable {
    private let rules: ArchitectureRules
    private let adapters: [RepositoryLanguageAdapter]

    public init(
        configuration: ArchitectureConfiguration,
        adapters: [RepositoryLanguageAdapter] = RepositoryLanguageAdapter.defaultAdapters
    ) throws {
        self.rules = try ArchitectureRules(configuration: configuration)
        self.adapters = adapters
    }

    public init(
        rules: ArchitectureRules,
        adapters: [RepositoryLanguageAdapter] = RepositoryLanguageAdapter.defaultAdapters
    ) {
        self.rules = rules
        self.adapters = adapters
    }

    public func scan(root: URL) async throws -> RepositoryFacts {
        let inputs = sourceFileInputs(in: root)

        let files = try await withThrowingTaskGroup(of: SourceFileFacts.self) { group in
            for input in inputs {
                guard let adapter = adapter(accepting: input.relativePath) else {
                    continue
                }
                group.addTask {
                    try await adapter.parse(input)
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

    private func sourceFileInputs(in root: URL) -> [SourceFileInput] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var inputs: [SourceFileInput] = []

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
                  adapter(accepting: typedRelativePath) != nil else {
                continue
            }

            inputs.append(
                SourceFileInput(
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

        guard let adapter = adapter(accepting: typedRelativePath) else {
            throw BumperError.unsupportedLanguage(relativePath)
        }

        return try await adapter.parse(
            SourceFileInput(
                url: url,
                relativePath: typedRelativePath,
            subsystem: subsystem.id,
            )
        )
    }

    private func adapter(accepting path: RelativeFilePath) -> RepositoryLanguageAdapter? {
        adapters.first { $0.accepts(path) }
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
