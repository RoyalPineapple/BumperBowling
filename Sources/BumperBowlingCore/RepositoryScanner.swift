import Foundation

public struct RepositoryScanLimits: Equatable, Sendable {
    public static let `default` = RepositoryScanLimits()

    public let maxFiles: Int
    public let maxFileBytes: UInt64
    public let maxTotalBytes: UInt64
    public let maxConcurrentParses: Int

    public init(
        maxFiles: Int = 20_000,
        maxFileBytes: UInt64 = 10 * 1024 * 1024,
        maxTotalBytes: UInt64 = 200 * 1024 * 1024,
        maxConcurrentParses: Int = 8
    ) {
        self.maxFiles = Swift.max(1, maxFiles)
        self.maxFileBytes = Swift.max(1, maxFileBytes)
        self.maxTotalBytes = Swift.max(1, maxTotalBytes)
        self.maxConcurrentParses = Swift.max(1, maxConcurrentParses)
    }
}

public struct RepositoryScanner: Sendable {
    private let rules: ArchitectureRules
    private let parser: SwiftFileParser
    private let limits: RepositoryScanLimits

    public init(
        configuration: ArchitectureConfiguration,
        parser: SwiftFileParser = SwiftFileParser(),
        limits: RepositoryScanLimits = .default
    ) throws {
        self.rules = try ArchitectureRules(configuration: configuration)
        self.parser = parser
        self.limits = limits
    }

    public init(
        rules: ArchitectureRules,
        parser: SwiftFileParser = SwiftFileParser(),
        limits: RepositoryScanLimits = .default
    ) {
        self.rules = rules
        self.parser = parser
        self.limits = limits
    }

    /// Reads bounded raw sources for the runner's `evaluate` mode. The host
    /// owns filesystem safety; parsing happens once, in the runner.
    public func scanSources(root: URL) async throws -> [SourceInput] {
        let root = root.standardizedFileURL
        return try sourceFileInputs(in: root)
            .map { input in
                guard let source = try? String(contentsOf: input.url, encoding: .utf8) else {
                    throw BumperError.unreadableFile(input.relativePath.rawValue)
                }
                return SourceInput(
                    path: input.relativePath,
                    component: input.component,
                    source: source
                )
            }
            .sorted { lhs, rhs in
                lhs.path.rawValue < rhs.path.rawValue
            }
    }

    public func scan(root: URL) async throws -> RepositoryFacts {
        let root = root.standardizedFileURL
        let inputs = try sourceFileInputs(in: root)

        var files: [SourceFileFacts] = []
        for start in stride(from: 0, to: inputs.count, by: limits.maxConcurrentParses) {
            let end = Swift.min(start + limits.maxConcurrentParses, inputs.count)
            let chunk = inputs[start..<end]

            let parsedFiles = try await withThrowingTaskGroup(of: SourceFileFacts.self) { group in
                for input in chunk {
                    let parser = parser
                    group.addTask {
                        try parser.parseFile(
                            at: input.url,
                            relativePath: input.relativePath,
                            component: input.component
                        )
                    }
                }

                var parsedFiles: [SourceFileFacts] = []
                for try await file in group {
                    parsedFiles.append(file)
                }
                return parsedFiles
            }

            files.append(contentsOf: parsedFiles)
        }

        return RepositoryFacts(files: files.sorted(by: { $0.path.rawValue < $1.path.rawValue }))
    }

    private func sourceFileInputs(in root: URL) throws -> [SwiftSourceFileInput] {
        let fileManager = FileManager.default
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var inputs: [SwiftSourceFileInput] = []
        var totalBytes: UInt64 = 0

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
                  let component = rules.component(containing: typedRelativePath),
                  isSwiftFile(typedRelativePath) else {
                continue
            }

            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            if resourceValues.isSymbolicLink == true {
                throw BumperError.unsafeSymlinkedSourceFile(typedRelativePath.rawValue)
            }
            guard resourceValues.isRegularFile == true else {
                continue
            }

            try Self.validateContainment(url: url, root: canonicalRoot, reportedPath: typedRelativePath.rawValue)

            let fileSize = UInt64(resourceValues.fileSize ?? 0)
            guard fileSize <= limits.maxFileBytes else {
                throw BumperError.sourceFileTooLarge(
                    typedRelativePath.rawValue,
                    fileSize,
                    limits.maxFileBytes
                )
            }
            totalBytes += fileSize
            guard totalBytes <= limits.maxTotalBytes else {
                throw BumperError.repositoryScanLimitExceeded(
                    "Swift source files exceed \(limits.maxTotalBytes) total bytes."
                )
            }
            guard inputs.count < limits.maxFiles else {
                throw BumperError.repositoryScanLimitExceeded(
                    "More than \(limits.maxFiles) Swift source files matched the configured paths."
                )
            }

            inputs.append(
                SwiftSourceFileInput(
                    url: url,
                    relativePath: typedRelativePath,
                    component: component.id
                )
            )
        }

        return inputs
    }

    public func scanFile(_ url: URL, root: URL) async throws -> SourceFileFacts {
        let root = root.standardizedFileURL
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        try Self.validateContainment(url: url, root: canonicalRoot, reportedPath: url.path)

        let relativePath = Self.relativePath(for: url, root: root)
        let typedRelativePath = try RelativeFilePath(relativePath)
        guard let component = rules.component(containing: typedRelativePath) else {
            throw BumperError.noComponentForFile(relativePath)
        }

        guard isSwiftFile(typedRelativePath) else {
            throw BumperError.unsupportedLanguage(relativePath)
        }

        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        if resourceValues.isSymbolicLink == true {
            throw BumperError.unsafeSymlinkedSourceFile(typedRelativePath.rawValue)
        }
        guard resourceValues.isRegularFile == true else {
            throw BumperError.unreadableFile(typedRelativePath.rawValue)
        }

        try Self.validateContainment(
            url: url,
            root: canonicalRoot,
            reportedPath: typedRelativePath.rawValue
        )

        let fileSize = UInt64(resourceValues.fileSize ?? 0)
        guard fileSize <= limits.maxFileBytes else {
            throw BumperError.sourceFileTooLarge(
                typedRelativePath.rawValue,
                fileSize,
                limits.maxFileBytes
            )
        }

        return try parser.parseFile(
            at: url,
            relativePath: typedRelativePath,
            component: component.id
        )
    }

    private func isSwiftFile(_ path: RelativeFilePath) -> Bool {
        StringMatcher.suffix(".swift").matches(path)
    }

    private func shouldSkip(_ relativePath: String) -> Bool {
        StringMatcher.prefix(".build/").matches(relativePath)
            || StringMatcher.prefix(".git/").matches(relativePath)
            || StringMatcher.prefix("DerivedData/").matches(relativePath)
    }

    private static func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path

        if StringMatcher.exact(rootPath).matches(filePath) {
            return ""
        }

        let prefix = StringMatcher.suffix("/").matches(rootPath) ? rootPath : rootPath + "/"
        if StringMatcher.prefix(prefix).matches(filePath) {
            return String(filePath.dropFirst(prefix.count))
        }

        return filePath
    }

    private static func validateContainment(url: URL, root: URL, reportedPath: String) throws {
        let rootPath = root.path
        let filePath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = StringMatcher.suffix("/").matches(rootPath) ? rootPath : rootPath + "/"
        guard StringMatcher.exact(rootPath).matches(filePath) || StringMatcher.prefix(prefix).matches(filePath) else {
            throw BumperError.sourceFileOutsideRoot(reportedPath, rootPath)
        }
    }
}

private struct SwiftSourceFileInput: Sendable {
    let url: URL
    let relativePath: RelativeFilePath
    let component: ComponentID
}
