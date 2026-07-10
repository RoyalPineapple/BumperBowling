import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Lint run engine")
struct LintRunEngineTests {
    @Test
    func `reducer starts by preparing rules`() {
        let configuration = ArchitectureConfiguration(components: [])
        let transition = LintRunReducer().reduce(
            state: .idle,
            event: .start(configuration)
        )

        expectPreparingRules(transition.state, configuration)
        #expect(transition.effect == .prepareRules(configuration))
    }

    @Test
    func `reducer scans after rules are prepared`() throws {
        let configuration = ArchitectureConfiguration(components: [])
        let preparedRules = LintPreparedRules(
            configuration: configuration,
            rules: try ArchitectureRules(configuration: configuration)
        )

        let transition = LintRunReducer().reduce(
            state: .preparingRules(configuration),
            event: .preparedRules(preparedRules)
        )

        expectScanningSources(transition.state, preparedRules)
        #expect(transition.effect == .scanSources(preparedRules))
    }

    @Test
    func `reducer evaluates rules after scanning sources`() throws {
        let configuration = ArchitectureConfiguration(components: [])
        let rules = try ArchitectureRules(configuration: configuration)
        let preparedRules = LintPreparedRules(configuration: configuration, rules: rules)
        let repository = RepositoryFacts(files: [])
        let plan = LintEvaluationPlan(configuration: configuration, rules: rules, repository: repository)

        let transition = LintRunReducer().reduce(
            state: .scanningSources(preparedRules),
            event: .scannedSources(preparedRules: preparedRules, repository: repository)
        )

        expectEvaluatingRules(transition.state, plan)
        #expect(transition.effect == .evaluateRules(plan))
    }

    @Test
    func `reducer reports after collecting findings`() throws {
        let configuration = ArchitectureConfiguration(components: [])
        let rules = try ArchitectureRules(configuration: configuration)
        let repository = RepositoryFacts(files: [])
        let plan = LintEvaluationPlan(configuration: configuration, rules: rules, repository: repository)
        let evaluation = LintRuleEvaluation(
            plan: plan,
            builtInReport: LintReport(violations: []),
            customRuleOutput: .empty
        )
        let report = LintReport(violations: [])
        let transition = LintRunReducer().reduce(
            state: .collectingFindings(evaluation),
            event: .collectedFindings(report)
        )

        expectReporting(transition.state, rules: rules, repository: repository, report: report)
        #expect(transition.effect == nil)
    }
}

private func expectPreparingRules(
    _ state: LintRunState,
    _ configuration: ArchitectureConfiguration
) {
    guard case .preparingRules(let actualConfiguration) = state else {
        Issue.record("Expected preparingRules state")
        return
    }
    #expect(actualConfiguration == configuration)
}

private func expectScanningSources(
    _ state: LintRunState,
    _ preparedRules: LintPreparedRules
) {
    guard case .scanningSources(let actualPreparedRules) = state else {
        Issue.record("Expected scanningSources state")
        return
    }
    #expect(actualPreparedRules == preparedRules)
}

private func expectEvaluatingRules(
    _ state: LintRunState,
    _ plan: LintEvaluationPlan
) {
    guard case .evaluatingRules(let actualPlan) = state else {
        Issue.record("Expected evaluatingRules state")
        return
    }
    #expect(actualPlan == plan)
}

private func expectReporting(
    _ state: LintRunState,
    rules: ArchitectureRules,
    repository: RepositoryFacts,
    report: LintReport
) {
    guard case .reporting(let result) = state else {
        Issue.record("Expected reporting state")
        return
    }
    #expect(result.rules == rules)
    #expect(result.repository == repository)
    #expect(result.report == report)
}
