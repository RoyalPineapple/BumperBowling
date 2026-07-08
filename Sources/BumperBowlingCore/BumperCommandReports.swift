import Foundation

public struct BumperProgressReporter: Sendable {
    private let handler: (@Sendable (String) -> Void)?

    public init(_ handler: (@Sendable (String) -> Void)? = nil) {
        self.handler = handler
    }

    public static let disabled = BumperProgressReporter()

    public func report(_ message: String) {
        handler?(message)
    }
}

public struct ScanReport: Equatable, Sendable, Codable {
    public let fileCount: Int
    public let components: [String]
    public let dependencies: [ScanDependency]

    public init(repository: RepositoryFacts) {
        self.fileCount = repository.files.count
        self.components = Set(repository.files.map(\.component.rawValue)).sorted()
        self.dependencies = repository.dependencyEdges
            .map(ScanDependency.init)
            .sorted { lhs, rhs in
                "\(lhs.sourceComponent).\(lhs.importedModule)" < "\(rhs.sourceComponent).\(rhs.importedModule)"
            }
    }

    public var markdownSummary: String {
        var lines: [String] = []
        lines.append("# Architecture Scan")
        lines.append("")
        lines.append("Files: \(fileCount)")
        lines.append("Components: \(components.joined(separator: ", "))")
        lines.append("")
        lines.append("## Dependencies")

        for dependency in dependencies {
            lines.append("- \(dependency.sourceComponent) imports \(dependency.importedModule)")
        }

        return lines.joined(separator: "\n")
    }
}

public struct ScanDependency: Equatable, Sendable, Codable {
    public let sourceComponent: String
    public let importedModule: String

    public init(sourceComponent: String, importedModule: String) {
        self.sourceComponent = sourceComponent
        self.importedModule = importedModule
    }

    public init(edge: DependencyEdge) {
        self.sourceComponent = edge.sourceComponent.rawValue
        self.importedModule = edge.importedModule.rawValue
    }
}

public struct LintRunResult: Sendable {
    public let rules: ArchitectureRules
    public let repository: RepositoryFacts
    public let report: LintReport

    public init(rules: ArchitectureRules, repository: RepositoryFacts, report: LintReport) {
        self.rules = rules
        self.repository = repository
        self.report = report
    }

    public var scannedFileCount: Int {
        repository.files.count
    }

    public var enabledRuleCount: Int {
        RuleRegistry(configuration: rules.ruleConfiguration).enabledRules.count
    }

    public func output(baseline: LintBaseline? = nil) -> LintOutput {
        LintOutput(
            report: report,
            rules: rules,
            baselineComparison: baseline.map { LintBaselineComparison(report: report, baseline: $0) }
        )
    }
}

public struct LintOutput: Equatable, Sendable, Codable {
    public let violations: [LintViolationOutput]
    public let summary: LintOutputSummary

    public init(
        report: LintReport,
        rules: ArchitectureRules,
        baselineComparison: LintBaselineComparison? = nil
    ) {
        let baseline = baselineComparison?.baseline
        self.violations = report.violations.map { violation in
            LintViolationOutput(
                violation: violation,
                component: rules.component(containing: violation.path)?.id.rawValue,
                baselineState: baseline.map { $0.contains(violation) ? .baseline : .new }
            )
        }
        self.summary = LintOutputSummary(
            totalViolations: report.violations.count,
            errorCount: report.violations.filter { $0.severity == .error }.count,
            warningCount: report.violations.filter { $0.severity == .warning }.count,
            noteCount: report.violations.filter { $0.severity == .note }.count,
            baseline: baselineComparison.map(LintBaselineOutputSummary.init)
        )
    }
}

public struct LintViolationOutput: Equatable, Sendable, Codable {
    public let ruleID: String
    public let severity: String
    public let component: String?
    public let path: String
    public let line: Int?
    public let column: Int?
    public let message: String
    public let observed: String?
    public let expected: String?
    public let baselineState: LintBaselineState?

    public init(
        violation: ArchitectureViolation,
        component: String?,
        baselineState: LintBaselineState? = nil
    ) {
        self.ruleID = violation.ruleID.rawValue
        self.severity = violation.severity.rawValue
        self.component = component
        self.path = violation.path.rawValue
        self.line = violation.location?.line
        self.column = violation.location?.column
        self.message = violation.message
        self.observed = violation.evidence?.observed
        self.expected = violation.evidence?.expectation
        self.baselineState = baselineState
    }
}

public struct LintOutputSummary: Equatable, Sendable, Codable {
    public let totalViolations: Int
    public let errorCount: Int
    public let warningCount: Int
    public let noteCount: Int
    public let baseline: LintBaselineOutputSummary?
}

public struct LintBaselineOutputSummary: Equatable, Sendable, Codable {
    public let baselineViolationCount: Int
    public let existingViolationCount: Int
    public let newViolationCount: Int
    public let resolvedViolationCount: Int

    public init(comparison: LintBaselineComparison) {
        self.baselineViolationCount = comparison.baseline.violations.count
        self.existingViolationCount = comparison.existingViolations.count
        self.newViolationCount = comparison.newViolations.count
        self.resolvedViolationCount = comparison.resolvedViolations.count
    }
}

public enum LintBaselineState: String, Equatable, Sendable, Codable {
    case baseline
    case new
}

public struct LintBaseline: Equatable, Sendable, Codable {
    public let version: Int
    public let violations: [LintBaselineViolation]

    public init(version: Int = 1, violations: [LintBaselineViolation]) {
        self.version = version
        self.violations = violations
    }

    public init(report: LintReport) {
        let entries = Set(report.violations.map(LintBaselineViolation.init))
        self.init(
            violations: entries.sorted { lhs, rhs in
                [
                    lhs.ruleID,
                    lhs.path,
                    lhs.message,
                    lhs.observed ?? "",
                    lhs.expected ?? ""
                ].joined(separator: "\u{0}") <
                    [
                        rhs.ruleID,
                        rhs.path,
                        rhs.message,
                        rhs.observed ?? "",
                        rhs.expected ?? ""
                    ].joined(separator: "\u{0}")
            }
        )
    }

    public func contains(_ violation: ArchitectureViolation) -> Bool {
        identities.contains(LintBaselineIdentity(violation: violation))
    }

    fileprivate var identities: Set<LintBaselineIdentity> {
        Set(violations.map(LintBaselineIdentity.init))
    }
}

public struct LintBaselineViolation: Hashable, Sendable, Codable {
    public let ruleID: String
    public let severity: String
    public let path: String
    public let line: Int?
    public let column: Int?
    public let message: String
    public let observed: String?
    public let expected: String?

    public init(_ violation: ArchitectureViolation) {
        self.ruleID = violation.ruleID.rawValue
        self.severity = violation.severity.rawValue
        self.path = violation.path.rawValue
        self.line = violation.location?.line
        self.column = violation.location?.column
        self.message = violation.message
        self.observed = violation.evidence?.observed
        self.expected = violation.evidence?.expectation
    }
}

public struct LintBaselineComparison: Equatable, Sendable {
    public let baseline: LintBaseline
    public let existingViolations: [ArchitectureViolation]
    public let newViolations: [ArchitectureViolation]
    public let resolvedViolations: [LintBaselineViolation]

    public init(report: LintReport, baseline: LintBaseline) {
        let currentIdentities = Set(report.violations.map { LintBaselineIdentity(violation: $0) })
        self.baseline = baseline
        self.existingViolations = report.violations.filter { baseline.contains($0) }
        self.newViolations = report.violations.filter { !baseline.contains($0) }
        self.resolvedViolations = baseline.violations.filter { entry in
            !currentIdentities.contains(LintBaselineIdentity(entry: entry))
        }
    }

    public var effectiveReport: LintReport {
        LintReport(violations: newViolations)
    }

    public var markdownSummary: String {
        var lines: [String] = []
        if newViolations.isEmpty {
            lines.append("No new architecture violations found.")
        } else {
            lines.append("New architecture violations found:")
            lines.append("")
            for violation in newViolations {
                let severity = violation.severity.rawValue.uppercased()
                lines.append(
                    "- [\(severity)] \(violation.markdownLocation): \(violation.message) " +
                        "(\(violation.ruleID.rawValue))"
                )
            }
        }
        lines.append("")
        let baselineSummary = [
            "\(existingViolations.count) existing",
            "\(newViolations.count) new",
            "\(resolvedViolations.count) resolved."
        ].joined(separator: ", ")
        lines.append(
            "Baseline: \(baselineSummary)"
        )
        return lines.joined(separator: "\n")
    }
}

private struct LintBaselineIdentity: Hashable {
    let ruleID: String
    let path: String
    let message: String
    let observed: String?
    let expected: String?

    init(violation: ArchitectureViolation) {
        self.ruleID = violation.ruleID.rawValue
        self.path = violation.path.rawValue
        self.message = violation.message
        self.observed = violation.evidence?.observed
        self.expected = violation.evidence?.expectation
    }

    init(entry: LintBaselineViolation) {
        self.ruleID = entry.ruleID
        self.path = entry.path
        self.message = entry.message
        self.observed = entry.observed
        self.expected = entry.expected
    }
}

public enum LintFailureThreshold: String, Equatable, Sendable {
    case none
    case note
    case warning
    case error

    public func shouldFail(_ report: LintReport) -> Bool {
        guard self != .none else {
            return false
        }
        return report.violations.contains { violation in
            violation.severity.rank >= severityRank
        }
    }

    private var severityRank: Int {
        switch self {
        case .none:
            Int.max
        case .note:
            Severity.note.rank
        case .warning:
            Severity.warning.rank
        case .error:
            Severity.error.rank
        }
    }
}

private extension Severity {
    var rank: Int {
        switch self {
        case .off:
            0
        case .note:
            1
        case .warning:
            2
        case .error:
            3
        }
    }
}
