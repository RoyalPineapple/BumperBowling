import Foundation

/// Wall-clock measurements from one rule evaluation run, for rule authors
/// diagnosing slow rules and fact providers. Fact durations are inclusive:
/// a provider that derives other facts is charged for its dependencies.
public struct EvaluationTelemetry: Codable, Equatable, Sendable {
    public struct Measurement: Codable, Equatable, Sendable {
        public let id: String
        public let seconds: Double

        public init(id: String, seconds: Double) {
            self.id = id
            self.seconds = seconds
        }
    }

    /// Per-rule evaluation durations, slowest first.
    public let ruleSeconds: [Measurement]
    /// Per-fact-provider derivation durations, slowest first. Each provider
    /// derives at most once per run.
    public let factSeconds: [Measurement]
    /// The whole evaluation, including rule identity validation.
    public let totalSeconds: Double

    public init(
        ruleSeconds: [Measurement],
        factSeconds: [Measurement],
        totalSeconds: Double
    ) {
        self.ruleSeconds = ruleSeconds.sorted { $0.seconds > $1.seconds }
        self.factSeconds = factSeconds.sorted { $0.seconds > $1.seconds }
        self.totalSeconds = totalSeconds
    }
}

/// One evaluation's canonical report plus its telemetry. The runner's
/// `evaluate` mode emits this value; `report` remains the one canonical
/// diagnostic projection.
public struct EvaluationRun: Codable, Equatable, Sendable {
    public let report: RuleReport
    public let telemetry: EvaluationTelemetry

    public init(report: RuleReport, telemetry: EvaluationTelemetry) {
        self.report = report
        self.telemetry = telemetry
    }
}

extension Duration {
    var secondsValue: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
