import Testing
import SwiftParser
import SwiftSyntax
@testable import BumperBowlingCore

@Suite("BumperConfiguration DSL")
struct BumperConfigurationDSLTests {
    @Test
    func buildsTypedArchitectureConfiguration() throws {
        let configuration = BumperConfiguration {
            Included {
                "Sources"
            }

            Excluded {
                ".build"
            }

            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    Modules("CoreKit")
                    DoesNotUse("XCTest", severity: .error)
                    Requires(.immutableStoredState, severity: .warning)
                    Disallows(.assignment, .mutableBinding, severity: .warning)
                }

                Component(.cli) {
                    Owns("Sources/CLI")
                    Modules("CLI")
                    MayDependOn(.core)
                }
            }

            Assertions {
                DependencyBoundaries(.error)
            }
        }.architectureConfiguration

        let rules = try ArchitectureRules(configuration: configuration)

        #expect(rules.includes(try RelativeFilePath("Sources/Core/Thing.swift")))
        #expect(!rules.includes(try RelativeFilePath(".build/debug/Thing.swift")))
        #expect(rules.forbiddenImports == Set([try ModuleName("XCTest")]))
        #expect(rules.ruleConfiguration.forbiddenImports.first?.paths == ["Sources/Core"])
        #expect(
            rules.ruleConfiguration.storedProperties.disallowances ==
                Set<StoredPropertyDisallowance>([.storedVar])
        )
        #expect(
            rules.ruleConfiguration.syntaxConstructs.disallowedConstructs ==
                Set<ImperativeConstruct>([.assignment, .mutableBinding])
        )
        #expect(rules.ruleConfiguration.storedProperties.paths == ["Sources/Core"])
        #expect(rules.ruleConfiguration.syntaxConstructs.paths == ["Sources/Core"])
    }

    @Test
    func exposesDisallowedPublicDeclarations() throws {
        let configuration = BumperConfiguration {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    DoesNot(Declare("bumperBowling"), severity: .error)
                }
            }
        }.architectureConfiguration

        let rules = try ArchitectureRules(configuration: configuration)

        #expect(rules.ruleConfiguration.publicDeclarations.severity == .error)
        #expect(rules.ruleConfiguration.publicDeclarations.paths == ["Sources/Core"])
        #expect(rules.ruleConfiguration.publicDeclarations.requiredNames.isEmpty)
        #expect(rules.ruleConfiguration.publicDeclarations.disallowedNames == [.exact("bumperBowling")])
    }

    @Test
    func exposesRequiredPublicDeclarations() throws {
        let configuration = BumperConfiguration {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    Declares("Reducer", severity: .warning)
                }
            }
        }.architectureConfiguration

        let rules = try ArchitectureRules(configuration: configuration)

        #expect(rules.ruleConfiguration.publicDeclarations.severity == .warning)
        #expect(rules.ruleConfiguration.publicDeclarations.paths == ["Sources/Core"])
        #expect(rules.ruleConfiguration.publicDeclarations.requiredNames == [.exact("Reducer")])
        #expect(rules.ruleConfiguration.publicDeclarations.disallowedNames.isEmpty)
    }

    @Test
    func invertsSyntaxPredicates() throws {
        let configuration = BumperConfiguration {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    DoesNot(ContainSyntax(.forceUnwrapExpr), severity: .error)
                }
            }
        }.architectureConfiguration

        let rules = try ArchitectureRules(configuration: configuration)

        #expect(rules.ruleConfiguration.syntaxKinds.severity == .error)
        #expect(rules.ruleConfiguration.syntaxKinds.paths == ["Sources/Core"])
        #expect(rules.ruleConfiguration.syntaxKinds.requiredKinds.isEmpty)
        #expect(rules.ruleConfiguration.syntaxKinds.disallowedKinds == [SyntaxKindName(.forceUnwrapExpr)])
    }

    @Test
    func configuresDirectStringMatchingBoundary() throws {
        let configuration = BumperConfiguration {
            Assertions {
                NoDirectStringMatching(
                    .error,
                    paths: ["Sources/BumperBowlingCore"],
                    except: ["Sources/BumperBowlingCore/StringMatcher.swift"]
                )
            }
        }.architectureConfiguration

        let rule = try ArchitectureRules(configuration: configuration).ruleConfiguration.syntaxConstructs

        #expect(rule.severity == .error)
        #expect(rule.paths == ["Sources/BumperBowlingCore"])
        #expect(rule.excludedPaths == ["Sources/BumperBowlingCore/StringMatcher.swift"])
        #expect(rule.disallowedConstructs == [.directStringMatch])
    }

    @Test
    func exposesForbiddenComponentDependencies() throws {
        let configuration = BumperConfiguration {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    DoesNotDependOn(.ui)
                }

                Component(.ui) {
                    Owns("Sources/UI")
                }
            }
        }.architectureConfiguration

        let rules = try ArchitectureRules(configuration: configuration)

        #expect(rules.subsystemByID[try SubsystemID("core")]?.forbiddenDependencies == Set([try SubsystemID("ui")]))
    }

    @Test
    func composesCustomSemanticRequirementsFromFactRules() throws {
        let valueCore = ComponentRequirement(
            .typedIdentity,
            .immutableStoredState,
            .computedState,
            .functionalCore
        )

        let configuration = BumperConfiguration {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    Requires(valueCore, severity: .error)
                }
            }
        }.architectureConfiguration

        let rules = try ArchitectureRules(configuration: configuration)

        #expect(
            rules.ruleConfiguration.storedProperties.disallowances ==
                Set<StoredPropertyDisallowance>([.rawStringIdentity, .storedVar, .storedProperty])
        )
        #expect(
            rules.ruleConfiguration.syntaxConstructs.disallowedConstructs ==
                Set<ImperativeConstruct>(
                    [.assignment, .loop, .mutableBinding, .inoutExpression, .mutatingDeclaration]
                )
        )
        #expect(rules.ruleConfiguration.storedProperties.paths == ["Sources/Core"])
        #expect(rules.ruleConfiguration.syntaxConstructs.paths == ["Sources/Core"])
    }

    @Test
    func appliesConsumerComponentAndAssertionShapes() throws {
        let domainShape = ComponentShape {
            MayUse(.foundation)
            Requires(.explicitDomainSurfaces, .immutableStoredState, severity: .error)
            Requires(.noOptionalStoredProperties, .noBoolStoredProperties, severity: .warning)
        }
        let globalShape = AssertionShape {
            DependencyBoundaries(.error)
            NoDirectStringMatching(.warning, paths: ["Sources/Core"], except: ["Sources/Core/StringMatcher.swift"])
        }

        let configuration = BumperConfiguration {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    Modules("Core")
                    Applies(domainShape)
                }
            }

            Assertions {
                Applies(globalShape)
            }
        }.architectureConfiguration

        let rules = try ArchitectureRules(configuration: configuration)

        #expect(rules.ruleConfiguration.subsystemBoundary == .error)
        #expect(rules.ruleConfiguration.forbiddenImports.first?.values == Capability.allCases
            .filter { $0 != .foundation }
            .flatMap(\.modules)
            .sorted())
        #expect(
            rules.ruleConfiguration.storedProperties.disallowances ==
                Set<StoredPropertyDisallowance>([
                    .any,
                    .broadExistential,
                    .storedVar,
                    .optionalState,
                    .boolState,
                ])
        )
        #expect(rules.ruleConfiguration.storedProperties.severity == .error)
        #expect(rules.ruleConfiguration.syntaxConstructs.disallowedConstructs == [.directStringMatch])
        #expect(rules.ruleConfiguration.syntaxConstructs.excludedPaths == ["Sources/Core/StringMatcher.swift"])
    }

    @Test
    func shippedSemanticRuleSetsLowerToFactRules() {
        #expect(
            ComponentRequirement.swiftBasics.factRules ==
                ComponentRequirement(
                    .explicitDomainSurfaces,
                    .typedIdentity,
                    .immutableStoredState
                ).factRules
        )
        #expect(ComponentRequirement.parserStateMachine.factRules == ComponentRequirement.enumStateMachine.factRules)
        #expect(
            ComponentRequirement.pureDomain.factRules ==
                ComponentRequirement(.swiftBasics, .functionalCore).factRules
        )
    }

    @Test
    func composesSyntaxKindRules() {
        let requirement = ComponentRequirement(
            RequireSyntax(.structDecl),
            DisallowSyntax(.forceUnwrapExpr),
            DisallowSyntax(.whileStmt)
        )

        #expect(requirement.factRules.contains(.requireSyntaxKind(.structDecl)))
        #expect(requirement.factRules.contains(.disallowSyntaxKind(.forceUnwrapExpr)))
        #expect(requirement.factRules.contains(.disallowSyntaxKind(.whileStmt)))
    }

    @Test
    func composesGenericPredicatesOverSwiftSyntaxNodes() throws {
        let source = """
        struct Model {
            var id: String
        }
        """
        let tree = Parser.parse(source: source)
        let visitor = FirstNodeVisitor<VariableDeclSyntax>(viewMode: .sourceAccurate)
        visitor.walk(tree)
        guard let variable = visitor.node else {
            Issue.record("Expected to find a variable declaration")
            return
        }
        let assertion = BumperSyntaxAssertion(
            VariableDeclSyntax.self,
            where: BumperSyntaxPredicate { node in
                node.bumper.isMutableBinding && !node.bumper.storedProperties().isEmpty
            }
        )

        #expect(variable.bumper.kind == SyntaxKind.variableDecl)
        #expect(variable.bumper.bindingNames == ["id"])
        #expect(variable.bumper.explicitTypeNames == ["String"])
        #expect(assertion.evaluate(variable) == true)
        #expect(assertion.evaluate(tree) == nil)
    }
}

private final class FirstNodeVisitor<Node: SyntaxProtocol>: SyntaxAnyVisitor {
    var node: Node?

    override func visitAny(_ syntax: Syntax) -> SyntaxVisitorContinueKind {
        guard node == nil else {
            return .skipChildren
        }

        if let typedNode = syntax.as(Node.self) {
            node = typedNode
            return .skipChildren
        }

        return .visitChildren
    }
}
