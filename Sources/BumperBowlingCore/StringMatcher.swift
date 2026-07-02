import Foundation

public protocol StringMatchable: Sendable {
    var rawValue: String { get }
}

public struct StringMatcher: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public enum Mode: String, Hashable, Sendable {
        case exact
        case contains
        case prefix
        case suffix
    }

    public let mode: Mode
    public let pattern: String

    public init(mode: Mode, pattern: String) {
        guard !pattern.isEmpty else {
            preconditionFailure("String matchers cannot be empty.")
        }

        self.mode = mode
        self.pattern = pattern
    }

    public init(stringLiteral value: String) {
        self = .exact(value)
    }

    public static func exact(_ pattern: String) -> StringMatcher {
        StringMatcher(mode: .exact, pattern: pattern)
    }

    public static func contains(_ pattern: String) -> StringMatcher {
        StringMatcher(mode: .contains, pattern: pattern)
    }

    public static func prefix(_ pattern: String) -> StringMatcher {
        StringMatcher(mode: .prefix, pattern: pattern)
    }

    public static func suffix(_ pattern: String) -> StringMatcher {
        StringMatcher(mode: .suffix, pattern: pattern)
    }

    public func matches(_ candidate: String) -> Bool {
        switch mode {
        case .exact:
            candidate == pattern
        case .contains:
            candidate.contains(pattern)
        case .prefix:
            candidate.hasPrefix(pattern)
        case .suffix:
            candidate.hasSuffix(pattern)
        }
    }

    public func matches<Value: StringMatchable>(_ candidate: Value) -> Bool {
        matches(candidate.rawValue)
    }

    public var description: String {
        switch mode {
        case .exact:
            pattern
        case .contains:
            ".contains(\(pattern))"
        case .prefix:
            ".prefix(\(pattern))"
        case .suffix:
            ".suffix(\(pattern))"
        }
    }
}

extension SubsystemID: StringMatchable {}
extension ModuleName: StringMatchable {}
extension RelativeFilePath: StringMatchable {}
extension RelativePathPrefix: StringMatchable {}
extension DeclarationName: StringMatchable {}
extension AttributeName: StringMatchable {}
extension TypeName: StringMatchable {}
