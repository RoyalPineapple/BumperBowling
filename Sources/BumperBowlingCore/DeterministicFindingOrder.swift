import Foundation

extension Array where Element == RuleViolation {
    func deterministicallySorted() -> [RuleViolation] {
        sorted { lhs, rhs in
            lhs.sortKey < rhs.sortKey
        }
    }
}

private extension RuleViolation {
    var sortKey: FindingSortKey {
        FindingSortKey(
            ruleID: rule.id.rawValue,
            severity: rule.severity.rawValue,
            path: path.rawValue,
            line: location?.line,
            column: location?.column,
            message: message
        )
    }
}

private struct FindingSortKey: Comparable {
    let ruleID: String
    let severity: String
    let path: String
    let line: Int?
    let column: Int?
    let message: String

    static func < (lhs: FindingSortKey, rhs: FindingSortKey) -> Bool {
        lhs.values.lexicographicallyPrecedes(rhs.values)
    }

    private var values: [String] {
        [
            path,
            padded(line),
            padded(column),
            ruleID,
            severity,
            message
        ]
    }

    private func padded(_ value: Int?) -> String {
        String(format: "%08d", value ?? 0)
    }
}
