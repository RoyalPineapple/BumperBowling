import Foundation

public struct SourceFileInput: Sendable {
    public let url: URL
    public let relativePath: RelativeFilePath
    public let subsystem: SubsystemID

    public init(url: URL, relativePath: RelativeFilePath, subsystem: SubsystemID) {
        self.url = url
        self.relativePath = relativePath
        self.subsystem = subsystem
    }
}

public enum RepositoryLanguageAdapter: Sendable {
    case swift(SwiftLanguageAdapter)

    public static let defaultAdapters: [RepositoryLanguageAdapter] = [
        .swift(SwiftLanguageAdapter()),
    ]

    public func accepts(_ path: RelativeFilePath) -> Bool {
        switch self {
        case .swift(let adapter):
            adapter.accepts(path)
        }
    }

    public func parse(_ input: SourceFileInput) async throws -> SourceFileFacts {
        switch self {
        case .swift(let adapter):
            try await adapter.parse(input)
        }
    }
}

public struct SwiftLanguageAdapter: Sendable {
    private let parser: SwiftFileParser

    public init(parser: SwiftFileParser = SwiftFileParser()) {
        self.parser = parser
    }

    public func accepts(_ path: RelativeFilePath) -> Bool {
        path.rawValue.hasSuffix(".swift")
    }

    public func parse(_ input: SourceFileInput) async throws -> SourceFileFacts {
        guard let source = try? String(contentsOf: input.url, encoding: .utf8) else {
            throw BumperError.unreadableFile(input.relativePath.rawValue)
        }

        let summary = parser.parse(source)
        return SourceFileFacts(
            language: .swift,
            path: input.relativePath,
            subsystem: input.subsystem,
            imports: summary.imports,
            publicDeclarations: summary.publicDeclarations,
            storedProperties: summary.storedProperties,
            enums: summary.enums
        )
    }
}
