import Foundation

struct LintRunEngine: Sendable {
    let root: URL
    let configuration: ArchitectureConfiguration
    let progress: BumperProgressReporter

    init(
        root: URL,
        configuration: ArchitectureConfiguration,
        progress: BumperProgressReporter = .disabled
    ) {
        self.root = root.standardizedFileURL
        self.configuration = configuration
        self.progress = progress
    }

    func run() async throws -> LintRunResult {
        let reducer = LintRunReducer()
        var state = LintRunState.idle
        var event = LintRunEvent.start(configuration)

        while true {
            let transition = reducer.reduce(state: state, event: event)
            state = transition.state
            progress.report(state.progressMessage)

            if case .reporting(let result) = state {
                return result
            }

            guard let effect = transition.effect else {
                throw BumperError.configurationOutputMalformed("lint run reached state without an effect")
            }

            do {
                event = try await perform(effect)
            } catch {
                let failure = LintRunFailure(message: String(describing: error))
                let failedTransition = reducer.reduce(state: state, event: .failed(failure))
                progress.report(failedTransition.state.progressMessage)
                throw error
            }
        }
    }

    private func perform(_ effect: LintRunEffect) async throws -> LintRunEvent {
        switch effect {
        case .prepareRules(let configuration):
            return .preparedRules(
                LintPreparedRules(
                    configuration: configuration,
                    rules: try ArchitectureRules(configuration: configuration)
                )
            )

        case .scanSources(let preparedRules):
            let repository = try await RepositoryScanner(rules: preparedRules.rules).scan(root: root)
            return .scannedSources(preparedRules: preparedRules, repository: repository)

        case .evaluateRules(let plan):
            async let builtInReport = ArchitectureLinter(rules: plan.rules)
                .lintConcurrently(plan.repository)
            async let customRuleOutput = evaluateCustomRules(plan)
            return .evaluatedRules(
                try await LintRuleEvaluation(
                    plan: plan,
                    builtInReport: builtInReport,
                    customRuleOutput: customRuleOutput
                )
            )

        case .collectFindings(let evaluation):
            let report = LintReport(
                violations: (
                    evaluation.builtInReport.violations
                        + evaluation.customRuleOutput.architectureViolations
                ).deterministicallySorted()
            )
            return .collectedFindings(report)
        }
    }

    private func evaluateCustomRules(_ plan: LintEvaluationPlan) async throws -> CustomRuleOutput {
        guard plan.configuration.customRules.enabled else {
            return .empty
        }

        let root = root
        let configuration = plan.configuration
        let repository = plan.repository

        return try await Task.detached {
            try ConfigurationLoader.runCustomRules(
                root: root,
                configuration: configuration,
                repository: repository
            )
        }.value
    }
}

struct LintRunReducer: Sendable {
    func reduce(state: LintRunState, event: LintRunEvent) -> LintRunTransition {
        switch (state, event) {
        case (.idle, .start(let configuration)):
            return LintRunTransition(
                state: .preparingRules(configuration),
                effect: .prepareRules(configuration)
            )

        case (.preparingRules, .preparedRules(let preparedRules)):
            return LintRunTransition(
                state: .scanningSources(preparedRules),
                effect: .scanSources(preparedRules)
            )

        case (.scanningSources, .scannedSources(let preparedRules, let repository)):
            let plan = LintEvaluationPlan(
                configuration: preparedRules.configuration,
                rules: preparedRules.rules,
                repository: repository
            )
            return LintRunTransition(
                state: .evaluatingRules(plan),
                effect: .evaluateRules(plan)
            )

        case (.evaluatingRules, .evaluatedRules(let evaluation)):
            return LintRunTransition(
                state: .collectingFindings(evaluation),
                effect: .collectFindings(evaluation)
            )

        case (.collectingFindings(let evaluation), .collectedFindings(let report)):
            let result = LintRunResult(
                rules: evaluation.plan.rules,
                repository: evaluation.plan.repository,
                report: report
            )
            return LintRunTransition(state: .reporting(result), effect: nil)

        case (_, .failed(let failure)):
            return LintRunTransition(state: .failed(failure), effect: nil)

        default:
            let failure = LintRunFailure(message: "invalid transition from \(state) on \(event)")
            return LintRunTransition(state: .failed(failure), effect: nil)
        }
    }
}

enum LintRunState: Sendable {
    case idle
    case preparingRules(ArchitectureConfiguration)
    case scanningSources(LintPreparedRules)
    case evaluatingRules(LintEvaluationPlan)
    case collectingFindings(LintRuleEvaluation)
    case reporting(LintRunResult)
    case failed(LintRunFailure)

    var progressMessage: String {
        switch self {
        case .idle:
            "Starting lint run"
        case .preparingRules:
            "Preparing architecture rules"
        case .scanningSources:
            "Scanning Swift source files"
        case .evaluatingRules(let plan):
            "Evaluating \(plan.enabledRuleCount) architecture rule(s)"
        case .collectingFindings:
            "Collecting architecture findings"
        case .reporting(let result):
            "Found \(result.report.violations.count) architecture violation(s)"
        case .failed(let failure):
            "Lint run failed: \(failure.message)"
        }
    }
}

enum LintRunEvent: Equatable, Sendable {
    case start(ArchitectureConfiguration)
    case preparedRules(LintPreparedRules)
    case scannedSources(preparedRules: LintPreparedRules, repository: RepositoryFacts)
    case evaluatedRules(LintRuleEvaluation)
    case collectedFindings(LintReport)
    case failed(LintRunFailure)
}

enum LintRunEffect: Sendable, Equatable {
    case prepareRules(ArchitectureConfiguration)
    case scanSources(LintPreparedRules)
    case evaluateRules(LintEvaluationPlan)
    case collectFindings(LintRuleEvaluation)
}

struct LintRunTransition: Sendable {
    let state: LintRunState
    let effect: LintRunEffect?
}

struct LintPreparedRules: Sendable, Equatable {
    let configuration: ArchitectureConfiguration
    let rules: ArchitectureRules
}

struct LintEvaluationPlan: Sendable, Equatable {
    let configuration: ArchitectureConfiguration
    let rules: ArchitectureRules
    let repository: RepositoryFacts

    var enabledRuleCount: Int {
        RuleRegistry(configuration: rules.ruleConfiguration).enabledRules.count
    }
}

struct LintRuleEvaluation: Sendable, Equatable {
    let plan: LintEvaluationPlan
    let builtInReport: LintReport
    let customRuleOutput: CustomRuleOutput
}

struct LintRunFailure: Error, Sendable, Equatable {
    let message: String
}
