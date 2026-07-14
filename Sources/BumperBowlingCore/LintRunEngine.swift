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
            let files = try await RepositoryScanner(rules: preparedRules.rules).scanSources(root: root)
            return .scannedSources(preparedRules: preparedRules, files: files)

        case .evaluateRules(let plan):
            let root = root
            let input = RepositoryInput(architecture: plan.configuration, files: plan.files)
            let configurationURL = root.appendingPathComponent(ConfigurationLoader.fileName)
            let report: RuleReport
            if FileManager.default.fileExists(atPath: configurationURL.path) {
                report = try await Task.detached {
                    try ConfigurationLoader.evaluateRules(root: root, input: input)
                }.value
            } else {
                // No authored BumperBowling.swift means no project rules, so
                // built-in rules evaluate in process without the runner.
                report = try RuleSet(rules: BuiltInRules.rules(from: input.architecture.rules))
                    .evaluate(configuration: input.architecture, repository: RepositorySyntax(input: input))
            }
            return .evaluatedRules(plan: plan, report: report)
        }
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

        case (.scanningSources, .scannedSources(let preparedRules, let files)):
            let plan = LintEvaluationPlan(
                configuration: preparedRules.configuration,
                rules: preparedRules.rules,
                files: files
            )
            return LintRunTransition(
                state: .evaluatingRules(plan),
                effect: .evaluateRules(plan)
            )

        case (.evaluatingRules, .evaluatedRules(let plan, let report)):
            let result = LintRunResult(
                rules: plan.rules,
                scannedFileCount: plan.files.count,
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
            "Evaluating rules over \(plan.files.count) source file(s)"
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
    case scannedSources(preparedRules: LintPreparedRules, files: [SourceInput])
    case evaluatedRules(plan: LintEvaluationPlan, report: RuleReport)
    case failed(LintRunFailure)
}

enum LintRunEffect: Sendable, Equatable {
    case prepareRules(ArchitectureConfiguration)
    case scanSources(LintPreparedRules)
    case evaluateRules(LintEvaluationPlan)
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
    let files: [SourceInput]
}

struct LintRunFailure: Error, Sendable, Equatable {
    let message: String
}
