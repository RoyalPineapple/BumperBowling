import Foundation

/// Rule identifiers are non-throwing values; literals are safe.
/// Throwing typed values (`RelativeFilePath`, `ComponentID`, ...) deliberately
/// have no literal conformance: string input validates at construction.
extension RuleID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}
