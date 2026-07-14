import Testing
import SwiftSyntax
@testable import BumperBowlingCore

@Suite("ArchitectureLinter")
struct ArchitectureLinterTests {
    @Test
    func graphCarriesSourceFactsAndDerivedEdges() throws {
        let file = SourceFileFacts(
            path: RelativeFilePath("Sources/UI/ViewModel.swift"),
            component: try ComponentID("ui"),
            imports: [try ModuleName("DomainKit")],
            publicDeclarations: [
                PublicDeclaration(kind: .struct, name: try DeclarationName("ViewModel")),
            ],
            storedProperties: [
                StoredProperty(name: try DeclarationName("id"), type: try TypeName("Identifier"), isMutable: false),
            ],
            enums: [try DeclarationName("ViewState")]
        )
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "ui", modules: ["UIKitFeature"], paths: ["Sources/UI"], mayDependOn: ["domain"]),
                ComponentConfiguration(name: "domain", modules: ["DomainKit"], paths: ["Sources/Domain"]),
            ]
        )
        let rules = try ArchitectureRules(configuration: configuration)

        let graph = ArchitectureGraph(nodes: RepositoryFacts(files: [file]), rules: rules)

        #expect(graph.sourceFiles == [file])
        #expect(graph.componentNodes == [try ComponentID("ui")])
        #expect(graph.moduleImportEdges == [
            DependencyEdge(sourceComponent: try ComponentID("ui"), importedModule: try ModuleName("DomainKit")),
        ])
        #expect(graph.componentImportEdges == [
            ComponentImportEdge(
                sourceComponent: try ComponentID("ui"),
                targetComponent: try ComponentID("domain"),
                importedModule: try ModuleName("DomainKit"),
                sourcePath: RelativeFilePath("Sources/UI/ViewModel.swift")
            ),
        ])
    }

    @Test
    func graphQueriesFactsInScope() throws {
        let uiFile = SourceFileFacts(
            path: RelativeFilePath("Sources/UI/ViewModel.swift"),
            component: try ComponentID("ui"),
            imports: [try ModuleName("DomainKit")],
            publicDeclarations: [
                PublicDeclaration(kind: .struct, name: try DeclarationName("ViewModel")),
            ],
            storedProperties: [
                StoredProperty(name: try DeclarationName("state"), type: try TypeName("ViewState"), isMutable: false),
            ],
            observedImperativeConstructs: [
                ObservedImperativeConstruct(construct: .assignment),
            ],
            syntaxNodes: SwiftSyntaxNodeCatalog(
                nodes: [
                    ObservedSyntaxNode(kind: .structDecl),
                ]
            )
        )
        let domainFile = SourceFileFacts(
            path: RelativeFilePath("Sources/Domain/Model.swift"),
            component: try ComponentID("domain"),
            imports: [],
            publicDeclarations: [
                PublicDeclaration(kind: .struct, name: try DeclarationName("Model")),
            ]
        )
        let rules = try ArchitectureRules(
            configuration: ArchitectureConfiguration(
                components: [
                    ComponentConfiguration(name: "ui", modules: ["UI"], paths: ["Sources/UI"]),
                    ComponentConfiguration(name: "domain", modules: ["DomainKit"], paths: ["Sources/Domain"]),
                ]
            )
        )
        let graph = ArchitectureGraph(nodes: RepositoryFacts(files: [uiFile, domainFile]), rules: rules)
        let uiScope = GraphScope(paths: [RelativePathPrefix("Sources/UI")])

        #expect(graph.files(in: uiScope).map(\.path) == [RelativeFilePath("Sources/UI/ViewModel.swift")])
        #expect(graph.imports(in: uiScope).map(\.module) == [try ModuleName("DomainKit")])
        #expect(graph.declarations(in: uiScope).map(\.declaration.name) == [try DeclarationName("ViewModel")])
        #expect(graph.storedProperties(in: uiScope).map(\.property.name) == [try DeclarationName("state")])
        #expect(graph.constructs(in: uiScope).map(\.construct.construct) == [.assignment])
        #expect(graph.syntaxNodes(in: uiScope).map(\.node.kind) == [.structDecl])
    }

    @Test
    func sourceFileFactsNormalizeCollectedFacts() throws {
        let file = SourceFileFacts(
            path: RelativeFilePath("Sources/Core/Model.swift"),
            component: try ComponentID("core"),
            nodes: [
                .importModule(try ModuleName("Zed")),
                .importModule(try ModuleName("Foundation")),
                .importModule(try ModuleName("Foundation")),
                .publicDeclaration(PublicDeclaration(kind: .struct, name: try DeclarationName("Model"))),
                .storedProperty(
                    StoredProperty(name: try DeclarationName("id"), type: try TypeName("ID"), isMutable: false)
                ),
                .enumDeclaration(try DeclarationName("ModelState")),
                .imperativeConstruct(ObservedImperativeConstruct(construct: .mutableBinding)),
                .syntax(ObservedSyntaxNode(kind: .structDecl)),
            ]
        )

        #expect(file.imports == [try ModuleName("Foundation"), try ModuleName("Zed")])
        #expect(file.publicDeclarations.map(\.name) == [try DeclarationName("Model")])
        #expect(file.storedProperties.map(\.name) == [try DeclarationName("id")])
        #expect(file.enums == [try DeclarationName("ModelState")])
        #expect(file.imperativeConstructs == [.mutableBinding])
        #expect(file.syntaxNodes.nodeKinds == [.structDecl])
    }

    @Test
    func flagsForbiddenImportsAndUndeclaredComponentDependencies() throws {
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "Recording", modules: ["RecordingKit"], paths: ["Sources/Recording"], mayDependOn: ["Core"]),
                ComponentConfiguration(name: "Playback", modules: ["PlaybackKit"], paths: ["Sources/Playback"]),
                ComponentConfiguration(name: "Core", modules: ["CoreKit"], paths: ["Sources/Core"]),
            ],
            rules: RuleConfiguration(
                forbiddenImports: RuleSetting(severity: .error, values: ["XCTest"]),
                componentBoundary: .error
            )
        )

        let nodes = RepositoryFacts(files: [
            SourceFileFacts(
                path: RelativeFilePath("Sources/Recording/Recorder.swift"),
                component: try ComponentID("Recording"),
                imports: [try ModuleName("CoreKit"), try ModuleName("PlaybackKit"), try ModuleName("XCTest")],
                publicDeclarations: []
            ),
        ])

        let report = try ArchitectureLinter(configuration: configuration).lint(nodes)
        let messages = report.violations.map(\ArchitectureViolation.message)

        #expect(messages.contains("recording imports undeclared component PlaybackKit (playback)"))
        #expect(messages.contains("recording imports forbidden module XCTest"))
    }

    @Test
    func warningSeverityDoesNotFailReport() throws {
        let file = SourceFileFacts(
            path: RelativeFilePath("Sources/Core/Thing.swift"),
            component: try ComponentID("core"),
            imports: [try ModuleName("XCTest")],
            publicDeclarations: []
        )
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "core", modules: ["Core"], paths: ["Sources/Core"]),
            ],
            rules: RuleConfiguration(
                forbiddenImports: RuleSetting(severity: .warning, values: ["XCTest"])
            )
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: [file]))

        #expect(report.violations.first?.severity == .warning)
        #expect(!report.hasErrors)
    }

    @Test
    func flagsStoredPropertyFactViolations() throws {
        let file = SourceFileFacts(
            path: RelativeFilePath("Sources/Core/Domain/Model.swift"),
            component: try ComponentID("core"),
            imports: [],
            nominalTypes: [
                NominalType(
                    kind: .struct,
                    name: try TypeName("Model"),
                    inheritedTypes: [try TypeName("Identifiable")]
                ),
            ],
            publicDeclarations: [],
            storedProperties: [
                StoredProperty(owner: try TypeName("Model"), name: try DeclarationName("id"), type: try TypeName("String"), isMutable: false),
                StoredProperty(owner: try TypeName("Model"), name: try DeclarationName("fullName"), type: try TypeName("String"), isMutable: false),
                StoredProperty(name: try DeclarationName("payload"), type: try TypeName("Any"), isMutable: true),
                StoredProperty(name: try DeclarationName("service"), type: try TypeName("any Service"), isMutable: false),
                StoredProperty(name: try DeclarationName("isReady"), type: try TypeName("Bool"), isMutable: false),
                StoredProperty(name: try DeclarationName("failure"), type: try TypeName("Failure?"), isMutable: false),
            ]
        )
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "core", modules: ["Core"], paths: ["Sources/Core"]),
            ],
            rules: RuleConfiguration(
                storedProperties: StoredPropertyRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/Core/Domain"],
                    disallowances: [
                        .any,
                        .boolState,
                        .broadExistential,
                        .optionalState,
                        .storedVar,
                        .rawStringIdentity,
                    ]
                )
            )
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: [file]))
        let messages = Set(report.violations.map(\.message))

        #expect(messages.contains("Stored property id uses raw String"))
        #expect(messages.contains("Stored property payload uses Any"))
        #expect(messages.contains("Stored property payload is mutable"))
        #expect(messages.contains("Stored property service uses a broad existential"))
        #expect(messages.contains("Stored property isReady uses Bool state"))
        #expect(messages.contains("Stored property failure uses optional state"))
        #expect(!messages.contains("Stored property fullName uses raw String"))
    }

    @Test
    func violationReceiptsCarryObservedFactEvidence() throws {
        let file = SourceFileFacts(
            path: RelativeFilePath("Sources/Core/Domain/Model.swift"),
            component: try ComponentID("core"),
            imports: [],
            nominalTypes: [
                NominalType(
                    kind: .struct,
                    name: try TypeName("Model"),
                    inheritedTypes: [try TypeName("Identifiable")]
                ),
            ],
            publicDeclarations: [],
            storedProperties: [
                StoredProperty(
                    owner: try TypeName("Model"),
                    name: try DeclarationName("id"),
                    type: try TypeName("String"),
                    isMutable: false,
                    location: SourcePosition(line: 3, column: 5)
                ),
            ]
        )
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "core", modules: ["Core"], paths: ["Sources/Core"]),
            ],
            rules: RuleConfiguration(
                storedProperties: StoredPropertyRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/Core/Domain"],
                    disallowances: [.rawStringIdentity]
                )
            )
        )

        let violation = try #require(
            try ArchitectureLinter(configuration: configuration)
                .lint(RepositoryFacts(files: [file]))
                .violations
                .first
        )

        #expect(violation.location == SourcePosition(line: 3, column: 5))
        #expect(violation.evidence?.observed == "stored property id: String")
        #expect(violation.evidence?.expectation == "Identifiable id properties must not use raw String")
        #expect(violation.markdownLocation == "Sources/Core/Domain/Model.swift:3:5")
    }

    @Test
    func flagsStoredPropertiesWhenComputedStateIsRequired() throws {
        let file = SourceFileFacts(
            path: RelativeFilePath("Sources/Core/Domain/Model.swift"),
            component: try ComponentID("core"),
            imports: [],
            publicDeclarations: [],
            storedProperties: [
                StoredProperty(name: try DeclarationName("fullName"), type: try TypeName("String"), isMutable: false),
            ]
        )
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "core", modules: ["Core"], paths: ["Sources/Core"]),
            ],
            rules: RuleConfiguration(
                storedProperties: StoredPropertyRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/Core/Domain"],
                    disallowances: [.storedProperty]
                )
            )
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: [file]))

        #expect(report.violations.map(\.message).contains("Stored property fullName is stored"))
    }

    @Test
    func flagsImperativeConstructsWhenFunctionalCoreIsRequired() throws {
        let file = SourceFileFacts(
            path: RelativeFilePath("Sources/Core/Domain/Reducer.swift"),
            component: try ComponentID("core"),
            imports: [],
            publicDeclarations: [],
            imperativeConstructs: [.mutableBinding, .assignment]
        )
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "core", modules: ["Core"], paths: ["Sources/Core"]),
            ],
            rules: RuleConfiguration(
                syntaxConstructs: SyntaxConstructRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/Core/Domain"],
                    disallowedConstructs: [.mutableBinding, .assignment]
                )
            )
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: [file]))
        let messages = Set(report.violations.map(\.message))

        #expect(messages.contains("Uses imperative construct mutableBinding"))
        #expect(messages.contains("Uses imperative construct assignment"))
    }

    @Test
    func skipsExcludedSyntaxConstructPaths() throws {
        let file = SourceFileFacts(
            path: RelativeFilePath("Sources/BumperBowlingCore/StringMatcher.swift"),
            component: try ComponentID("core"),
            imports: [],
            publicDeclarations: [],
            imperativeConstructs: [.directStringMatch]
        )
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(
                    name: "core",
                    modules: ["BumperBowlingCore"],
                    paths: ["Sources/BumperBowlingCore"]
                ),
            ],
            rules: RuleConfiguration(
                syntaxConstructs: SyntaxConstructRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/BumperBowlingCore"],
                    excludedPaths: ["Sources/BumperBowlingCore/StringMatcher.swift"],
                    disallowedConstructs: [.directStringMatch]
                )
            )
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: [file]))

        #expect(report.violations.isEmpty)
    }

    @Test
    func flagsParserWithoutEnumStateMachine() throws {
        let file = SourceFileFacts(
            path: RelativeFilePath("Sources/Core/FooParser.swift"),
            component: try ComponentID("core"),
            imports: [],
            publicDeclarations: [],
            enums: [try DeclarationName("Token")]
        )
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "core", modules: ["Core"], paths: ["Sources/Core"]),
            ],
            rules: RuleConfiguration(
                enumStateMachine: PathRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/**/*Parser.swift"]
                )
            )
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: [file]))

        #expect(report.violations.map(\.ruleID).contains(.enumStateMachine))
    }

    @Test
    func evaluatesGenericSwiftSyntaxKindRules() throws {
        let file = SourceFileFacts(
            path: RelativeFilePath("Sources/Core/Thing.swift"),
            component: try ComponentID("core"),
            imports: [],
            publicDeclarations: [],
            syntaxNodes: SwiftSyntaxNodeCatalog(
                nodeKinds: [.sourceFile, .structDecl, .forceUnwrapExpr]
            )
        )
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "core", modules: ["Core"], paths: ["Sources/Core"]),
            ],
            rules: RuleConfiguration(
                syntaxKinds: SyntaxKindRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/Core"],
                    requiredKinds: [.enumDecl],
                    disallowedKinds: [.forceUnwrapExpr]
                )
            )
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: [file]))
        let messages = Set(report.violations.map(\.message))

        #expect(report.violations.allSatisfy { $0.ruleID == .syntaxKinds })
        #expect(messages.contains("Missing required SwiftSyntax node kind enumDecl"))
        #expect(messages.contains("Uses disallowed SwiftSyntax node kind forceUnwrapExpr"))
    }

    @Test
    func flagsDisallowedPublicDeclarations() throws {
        let file = SourceFileFacts(
            path: RelativeFilePath("Sources/BumperBowlingCore/ArchitectureConfiguration.swift"),
            component: try ComponentID("core"),
            imports: [],
            publicDeclarations: [
                PublicDeclaration(kind: .variable, name: try DeclarationName("bumperBowling")),
            ]
        )
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(
                    name: "core",
                    modules: ["BumperBowlingCore"],
                    paths: ["Sources/BumperBowlingCore"]
                ),
            ],
            rules: RuleConfiguration(
                publicDeclarations: PublicDeclarationRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/BumperBowlingCore"],
                    disallowedNames: [.exact("bumperBowling")]
                )
            )
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: [file]))

        #expect(report.violations.map(\.ruleID) == [.publicDeclarations])
        #expect(report.violations.map(\.message) == ["Public declaration bumperBowling is disallowed"])
    }

    @Test
    func flagsMissingRequiredPublicDeclarations() throws {
        let file = SourceFileFacts(
            path: RelativeFilePath("Sources/BumperBowlingCore/Reducer.swift"),
            component: try ComponentID("core"),
            imports: [],
            publicDeclarations: [
                PublicDeclaration(kind: .struct, name: try DeclarationName("Reducer")),
            ]
        )
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(
                    name: "core",
                    modules: ["BumperBowlingCore"],
                    paths: ["Sources/BumperBowlingCore"]
                ),
            ],
            rules: RuleConfiguration(
                publicDeclarations: PublicDeclarationRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/BumperBowlingCore"],
                    requiredNames: [.exact("Reducer"), .exact("ReducerTests")]
                )
            )
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: [file]))

        #expect(report.violations.map(\.ruleID) == [.publicDeclarations])
        #expect(report.violations.map(\.message) == ["Missing required public declaration ReducerTests"])
    }

    @Test
    func flagsDependencyCycle() throws {
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "core", modules: ["Core"], paths: ["Sources/Core"], mayDependOn: ["ui"]),
                ComponentConfiguration(name: "ui", modules: ["UI"], paths: ["Sources/UI"], mayDependOn: ["core"]),
            ],
            rules: RuleConfiguration(declaredDependencyCycle: .error)
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: []))

        #expect(report.violations.map(\.ruleID).contains(.declaredDependencyCycle))
    }

    @Test
    func flagsDuplicatePathOwnershipWithConfiguredSeverity() throws {
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "core", paths: ["Sources/Core"]),
                ComponentConfiguration(name: "models", paths: ["Sources/Core/Models"]),
            ],
            rules: RuleConfiguration(duplicateOwnership: .warning)
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: []))

        let violation = try #require(report.violations.first)
        #expect(violation.ruleID == .duplicateOwnership)
        #expect(violation.severity == .warning)
        #expect(violation.path == (RelativeFilePath("Sources/Core/Models")))
        #expect(violation.message == "models path Sources/Core/Models overlaps core path Sources/Core")
        #expect(!report.hasErrors)
    }
}
