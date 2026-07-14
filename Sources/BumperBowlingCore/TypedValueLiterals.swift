import Foundation

/// Rule identifiers are non-throwing values; literals are safe.
extension RuleID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

/// Typed paths accept string literals only at the authoring boundary and
/// normalize immediately. A malformed literal is a loud configuration error,
/// never an empty scope that silently passes. Runtime string input still uses
/// the throwing initializers.
extension RelativeFilePath: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        guard let path = try? RelativeFilePath(value) else {
            preconditionFailure("Invalid relative file path literal: \(value)")
        }
        self = path
    }
}

extension RelativePathPrefix: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        guard let prefix = try? RelativePathPrefix(value) else {
            preconditionFailure("Invalid relative path prefix literal: \(value)")
        }
        self = prefix
    }
}
