import Foundation

extension Array where Element == ArchitectureViolation {
    func deterministicallySorted() -> [ArchitectureViolation] {
        sorted { lhs, rhs in
            lhs.sortKey < rhs.sortKey
        }
    }
}

extension Array where Element == CustomRuleFinding {
    func deterministicallySorted() -> [CustomRuleFinding] {
        sorted { lhs, rhs in
            lhs.sortKey < rhs.sortKey
        }
    }
}

private extension ArchitectureViolation {
    var sortKey: FindingSortKey {
        FindingSortKey(
            ruleID: ruleID.rawValue,
            severity: severity.rawValue,
            path: path.rawValue,
            line: location?.line,
            column: location?.column,
            message: message
        )
    }
}

private extension CustomRuleFinding {
    var sortKey: FindingSortKey {
        FindingSortKey(
            ruleID: ruleID.rawValue,
            severity: severity.rawValue,
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
