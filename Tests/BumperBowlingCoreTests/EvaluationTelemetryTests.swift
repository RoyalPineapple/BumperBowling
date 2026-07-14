import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Evaluation telemetry")
struct EvaluationTelemetryTests {
    private func repository() -> RepositorySyntax {
        RepositorySyntax(
            input: RepositoryInput(
                architecture: ArchitectureConfiguration(components: []),
                files: [
                    SourceInput(
                        path: "Sources/Core/A.swift",
                        component: try! ComponentID("core"),
                        source: "struct A { func run() {} }"
                    ),
                ]
            )
        )
    }

    @Test
    func evaluationRunMeasuresEveryRule() throws {
        let rules = RuleSet {
            Rules.repository("telemetry.first") { _ in [] }
            Rules.repository("telemetry.second") { _ in [] }
        }

        let run = try rules.evaluationRun(
            configuration: ArchitectureConfiguration(components: []),
            repository: repository()
        )

        #expect(Set(run.telemetry.ruleSeconds.map(\.id)) == ["telemetry.first", "telemetry.second"])
        #expect(run.telemetry.ruleSeconds.allSatisfy { $0.seconds >= 0 })
        #expect(run.telemetry.totalSeconds >= 0)
        #expect(run.report.violations.isEmpty)
    }

    @Test
    func factDerivationsAreMeasuredOncePerRun() throws {
        let rules = RuleSet {
            Rules.repository("telemetry.facts.one") { context in
                _ = try context.facts(BuiltInFacts.declarations)
                return []
            }
            Rules.repository("telemetry.facts.two") { context in
                _ = try context.facts(BuiltInFacts.declarations)
                return []
            }
        }

        let run = try rules.evaluationRun(
            configuration: ArchitectureConfiguration(components: []),
            repository: repository()
        )

        let declarationMeasurements = run.telemetry.factSeconds.filter { measurement in
            measurement.id == "bumper.declaration_inventory"
        }
        #expect(declarationMeasurements.count == 1, "memoized facts derive and measure once per run")
        #expect(declarationMeasurements.allSatisfy { $0.seconds >= 0 })
    }

    @Test
    func measurementsSortSlowestFirst() throws {
        let telemetry = EvaluationTelemetry(
            ruleSeconds: [
                EvaluationTelemetry.Measurement(id: "fast", seconds: 0.1),
                EvaluationTelemetry.Measurement(id: "slow", seconds: 2.0),
            ],
            factSeconds: [],
            totalSeconds: 2.1
        )

        #expect(telemetry.ruleSeconds.map(\.id) == ["slow", "fast"])
    }

    @Test
    func evaluationRunRoundTripsThroughJSON() throws {
        let rules = RuleSet {
            Rules.repository("telemetry.codable") { context in
                _ = try context.facts(BuiltInFacts.declarations)
                return []
            }
        }
        let run = try rules.evaluationRun(
            configuration: ArchitectureConfiguration(components: []),
            repository: repository()
        )

        let encoded = try JSONEncoder().encode(run)
        let decoded = try JSONDecoder().decode(EvaluationRun.self, from: encoded)

        #expect(decoded == run)
    }

    @Test
    func projectEvaluationRunCarriesTelemetryAndMatchesEvaluate() throws {
        let project = BumperProject {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                }
            }

            Rules {
                Rules.repository("telemetry.project") { _ in [] }
            }
        }
        let input = RepositoryInput(
            architecture: project.architecture,
            files: [
                SourceInput(
                    path: "Sources/Core/A.swift",
                    component: try! ComponentID("core"),
                    source: "struct A {}"
                ),
            ]
        )

        let run = try project.evaluationRun(input)

        #expect(run.telemetry.ruleSeconds.contains { $0.id == "telemetry.project" })
        #expect(try project.evaluate(input) == run.report)
    }
}
