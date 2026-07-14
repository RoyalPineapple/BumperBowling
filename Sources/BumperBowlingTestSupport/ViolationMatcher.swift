import BumperBowlingCore

/// A pure predicate over one canonical violation. Every expectation is
/// optional; an omitted field matches anything. Framework-neutral: assert on
/// the returned `Bool` from Swift Testing or XCTest alike.
public struct ViolationMatcher: Sendable {
    private let id: RuleID?
    private let path: RelativeFilePath?
    private let location: SourcePosition?
    private let message: StringMatcher?
    private let observed: StringMatcher?
    private let expectation: StringMatcher?
    private let details: [EvidenceDetail]

    public init(
        id: RuleID? = nil,
        path: RelativeFilePath? = nil,
        location: SourcePosition? = nil,
        message: StringMatcher? = nil,
        observed: StringMatcher? = nil,
        expectation: StringMatcher? = nil,
        details: [EvidenceDetail] = []
    ) {
        self.id = id
        self.path = path
        self.location = location
        self.message = message
        self.observed = observed
        self.expectation = expectation
        self.details = details
    }

    public func matches(_ violation: RuleViolation) -> Bool {
        if let id, violation.rule.id != id {
            return false
        }
        if let path, violation.path != path {
            return false
        }
        if let location, violation.location != location {
            return false
        }
        if let message, !message.matches(violation.message) {
            return false
        }
        if let observed, !observed.matches(violation.evidence?.observed ?? "") {
            return false
        }
        if let expectation, !expectation.matches(violation.evidence?.expectation ?? "") {
            return false
        }
        return details.allSatisfy { detail in
            violation.evidence?.details.contains(detail) == true
        }
    }
}

extension RuleReport {
    /// The violations satisfying one pure matcher.
    public func violations(matching matcher: ViolationMatcher) -> [RuleViolation] {
        violations.filter { violation in
            matcher.matches(violation)
        }
    }

    /// Whether any violation satisfies the matcher.
    public func contains(_ matcher: ViolationMatcher) -> Bool {
        !violations(matching: matcher).isEmpty
    }
}
