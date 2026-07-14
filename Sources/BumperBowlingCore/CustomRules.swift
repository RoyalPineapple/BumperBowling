import Foundation
import SwiftParser
import SwiftSyntax

public struct CustomRuleInput: Equatable, Sendable, Codable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let configuration: ArchitectureConfiguration
    public let files: [CustomRuleFileFacts]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        configuration: ArchitectureConfiguration,
        files: [CustomRuleFileFacts]
    ) {
        self.schemaVersion = schemaVersion
        self.configuration = configuration
        self.files = files
    }

    public init(configuration: ArchitectureConfiguration, repository: RepositoryFacts) {
        self.init(
            configuration: configuration,
            files: repository.files.map(CustomRuleFileFacts.init)
        )
    }
}

public struct CustomRuleFileFacts: Equatable, Sendable, Codable {
    public let path: RelativeFilePath
    public let component: String
    public let source: String?
    public let imports: [String]
    public let nominalTypes: [CustomRuleNominalTypeFact]
    public let extensionDeclarations: [CustomRuleExtensionFact]
    public let publicDeclarations: [CustomRulePublicDeclarationFact]
    public let storedProperties: [CustomRuleStoredPropertyFact]
    public let enums: [String]
    public let imperativeConstructs: [CustomRuleImperativeConstructFact]

    public init(
        path: RelativeFilePath,
        component: String,
        source: String? = nil,
        imports: [String],
        nominalTypes: [CustomRuleNominalTypeFact] = [],
        extensionDeclarations: [CustomRuleExtensionFact] = [],
        publicDeclarations: [CustomRulePublicDeclarationFact] = [],
        storedProperties: [CustomRuleStoredPropertyFact] = [],
        enums: [String] = [],
        imperativeConstructs: [CustomRuleImperativeConstructFact] = []
    ) {
        self.path = path
        self.component = component
        self.source = source
        self.imports = imports
        self.nominalTypes = nominalTypes
        self.extensionDeclarations = extensionDeclarations
        self.publicDeclarations = publicDeclarations
        self.storedProperties = storedProperties
        self.enums = enums
        self.imperativeConstructs = imperativeConstructs
    }

    public init(file: SourceFileFacts) {
        self.init(
            path: file.path,
            component: file.component.rawValue,
            source: file.source,
            imports: file.imports.map(\.rawValue),
            nominalTypes: file.nominalTypes.map(CustomRuleNominalTypeFact.init),
            extensionDeclarations: file.extensionDeclarations.map(CustomRuleExtensionFact.init),
            publicDeclarations: file.publicDeclarations.map(CustomRulePublicDeclarationFact.init),
            storedProperties: file.storedProperties.map(CustomRuleStoredPropertyFact.init),
            enums: file.enums.map(\.rawValue),
            imperativeConstructs: file.observedImperativeConstructs.map(CustomRuleImperativeConstructFact.init)
        )
    }
}

public struct CustomRuleNominalTypeFact: Equatable, Sendable, Codable {
    public let kind: String
    public let name: String
    public let access: String
    public let inheritedTypes: [String]
    public let attributes: [String]
    public let location: SourcePosition?

    public init(
        kind: String,
        name: String,
        access: String,
        inheritedTypes: [String] = [],
        attributes: [String] = [],
        location: SourcePosition? = nil
    ) {
        self.kind = kind
        self.name = name
        self.access = access
        self.inheritedTypes = inheritedTypes
        self.attributes = attributes
        self.location = location
    }

    public init(type: NominalType) {
        self.init(
            kind: type.kind.rawValue,
            name: type.name.rawValue,
            access: type.access.rawValue,
            inheritedTypes: type.inheritedTypes.map(\.rawValue),
            attributes: type.attributes.map(\.rawValue),
            location: type.location
        )
    }
}

public struct CustomRuleExtensionFact: Equatable, Sendable, Codable {
    public let extendedType: String
    public let access: String
    public let inheritedTypes: [String]
    public let attributes: [String]
    public let location: SourcePosition?

    public init(
        extendedType: String,
        access: String,
        inheritedTypes: [String] = [],
        attributes: [String] = [],
        location: SourcePosition? = nil
    ) {
        self.extendedType = extendedType
        self.access = access
        self.inheritedTypes = inheritedTypes
        self.attributes = attributes
        self.location = location
    }

    public init(declaration: ExtensionDeclaration) {
        self.init(
            extendedType: declaration.extendedType.rawValue,
            access: declaration.access.rawValue,
            inheritedTypes: declaration.inheritedTypes.map(\.rawValue),
            attributes: declaration.attributes.map(\.rawValue),
            location: declaration.location
        )
    }
}

public struct CustomRulePublicDeclarationFact: Equatable, Sendable, Codable {
    public let kind: String
    public let name: String
    public let attributes: [String]
    public let location: SourcePosition?

    public init(
        kind: String,
        name: String,
        attributes: [String] = [],
        location: SourcePosition? = nil
    ) {
        self.kind = kind
        self.name = name
        self.attributes = attributes
        self.location = location
    }

    public init(declaration: PublicDeclaration) {
        self.init(
            kind: declaration.kind.rawValue,
            name: declaration.name.rawValue,
            attributes: declaration.attributes.map(\.rawValue),
            location: declaration.location
        )
    }
}

public struct CustomRuleStoredPropertyFact: Equatable, Sendable, Codable {
    public let owner: String?
    public let name: String
    public let type: String?
    public let access: String
    public let attributes: [String]
    public let isMutable: Bool
    public let location: SourcePosition?

    public init(
        owner: String? = nil,
        name: String,
        type: String?,
        access: String,
        attributes: [String] = [],
        isMutable: Bool,
        location: SourcePosition? = nil
    ) {
        self.owner = owner
        self.name = name
        self.type = type
        self.access = access
        self.attributes = attributes
        self.isMutable = isMutable
        self.location = location
    }

    public init(property: StoredProperty) {
        self.init(
            owner: property.owner?.rawValue,
            name: property.name.rawValue,
            type: property.type?.rawValue,
            access: property.access.rawValue,
            attributes: property.attributes.map(\.rawValue),
            isMutable: property.isMutable,
            location: property.location
        )
    }
}

public struct CustomRuleImperativeConstructFact: Equatable, Sendable, Codable {
    public let construct: ImperativeConstruct
    public let location: SourcePosition?

    public init(construct: ImperativeConstruct, location: SourcePosition? = nil) {
        self.construct = construct
        self.location = location
    }

    public init(construct: ObservedImperativeConstruct) {
        self.init(construct: construct.construct, location: construct.location)
    }
}

public struct CustomRuleContext: Sendable {
    public let input: CustomRuleInput
    private let parsedSourceFiles: [SourceFileContext]

    public init(input: CustomRuleInput) {
        self.input = input
        self.parsedSourceFiles = input.files.compactMap(SourceFileContext.init)
    }

    init(context: RuleContext) {
        self.input = CustomRuleInput(
            configuration: context.configuration,
            files: context.repository.fileFacts
        )
        self.parsedSourceFiles = context.repository.files
    }

    public var files: [CustomRuleFileFacts] {
        input.files
    }

    public var sourceFiles: [SourceFileContext] {
        parsedSourceFiles
    }

    public func files(inComponent component: String) -> [CustomRuleFileFacts] {
        files.filter { StringMatcher.exact(component).matches($0.component) }
    }

    public func sourceFiles(inComponent component: String) -> [SourceFileContext] {
        sourceFiles.filter { StringMatcher.exact(component).matches($0.component) }
    }

    public func files(under prefix: String) -> [CustomRuleFileFacts] {
        guard let prefix = try? RelativePathPrefix(prefix) else {
            return []
        }
        return files.filter { prefix.contains($0.path) }
    }

    public func sourceFiles(under prefix: String) -> [SourceFileContext] {
        guard let prefix = try? RelativePathPrefix(prefix) else {
            return []
        }
        return sourceFiles.filter { prefix.contains($0.path) }
    }
}

/// One parsed source file: typed descriptor, source text, syntax, location
/// conversion, and failure construction.
public struct SourceFileContext: Sendable {
    public let facts: CustomRuleFileFacts
    public let descriptor: SourceFileDescriptor
    public let source: String
    public let syntax: SourceFileSyntax
    public let locationConverter: SourceLocationConverter

    public init?(facts: CustomRuleFileFacts) {
        guard let source = facts.source,
              let component = try? ComponentID(facts.component) else {
            return nil
        }

        let syntax = Parser.parse(source: source)
        self.facts = facts
        self.descriptor = SourceFileDescriptor(path: facts.path, component: component)
        self.source = source
        self.syntax = syntax
        self.locationConverter = SourceLocationConverter(fileName: facts.path.rawValue, tree: syntax)
    }

    /// Missing source text is an explicit failure, not a skipped file.
    public init(file: SourceFileFacts) throws {
        guard file.source != nil,
              let context = SourceFileContext(facts: CustomRuleFileFacts(file: file)) else {
            throw RuleEvaluationError.missingSource(file.path)
        }
        self = context
    }

    public var path: RelativeFilePath {
        descriptor.path
    }

    public var component: ComponentID {
        descriptor.component
    }

    public var imports: [String] {
        facts.imports
    }

    public func position(of node: some SyntaxProtocol) -> SourcePosition {
        let sourceLocation = locationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        return SourcePosition(line: sourceLocation.line, column: sourceLocation.column)
    }

    func location(for node: some SyntaxProtocol) -> SourcePosition {
        position(of: node)
    }

    public func failure(
        at node: some SyntaxProtocol,
        message: String,
        evidence: ViolationEvidence? = nil
    ) -> RuleFailure {
        RuleFailure(
            path: path,
            location: position(of: node),
            message: message,
            evidence: evidence
        )
    }
}

/// The former parallel failure currency, converged on `RuleFailure`.
public typealias CustomRuleFailure = RuleFailure

/// A repository-fact closure rule. Conforms to `RuleDefinition`, so it enters
/// the same engine and report as every other rule.
public struct CustomRule: RuleDefinition {
    public let id: RuleID
    public let severity: Severity
    private let evaluateFailures: @Sendable (CustomRuleContext) -> [RuleFailure]

    public init(
        _ id: RuleID,
        severity: Severity = .error,
        evaluate: @escaping @Sendable (CustomRuleContext) -> [RuleFailure]
    ) {
        self.id = id
        self.severity = severity
        self.evaluateFailures = evaluate
    }

    public init(
        _ id: String,
        severity: Severity = .error,
        evaluate: @escaping @Sendable (CustomRuleContext) -> [RuleFailure]
    ) {
        self.init(RuleID(id), severity: severity, evaluate: evaluate)
    }

    public var metadata: RuleMetadata {
        RuleMetadata(id: id, severity: severity, summary: "Project-defined repository rule.")
    }

    public var scope: RuleScope {
        .repository
    }

    public func evaluate(in context: RuleContext) throws -> [RuleFailure] {
        evaluateFailures(CustomRuleContext(context: context))
    }

    public func evaluate(in context: CustomRuleContext) -> [CustomRuleFinding] {
        evaluateFailures(context).map { failure in
            CustomRuleFinding(
                ruleID: id,
                severity: severity,
                path: failure.path,
                location: failure.location,
                message: failure.message,
                evidence: failure.evidence
            )
        }
    }
}

/// A per-file syntax closure rule over the same engine.
public struct CustomSyntaxRule: RuleDefinition {
    public let id: RuleID
    public let severity: Severity
    private let evaluateFile: @Sendable (SourceFileContext) -> [RuleFailure]

    public init(
        _ id: RuleID,
        severity: Severity = .error,
        evaluate: @escaping @Sendable (SourceFileContext) -> [RuleFailure]
    ) {
        self.id = id
        self.severity = severity
        self.evaluateFile = evaluate
    }

    public init(
        _ id: String,
        severity: Severity = .error,
        evaluate: @escaping @Sendable (SourceFileContext) -> [RuleFailure]
    ) {
        self.init(RuleID(id), severity: severity, evaluate: evaluate)
    }

    public var metadata: RuleMetadata {
        RuleMetadata(id: id, severity: severity, summary: "Project-defined syntax rule.")
    }

    public var scope: RuleScope {
        .repository
    }

    public func evaluate(in context: RuleContext) throws -> [RuleFailure] {
        context.files(in: scope).flatMap(evaluateFile)
    }
}

/// Project rule sets are ordinary `RuleSet`s; one builder, one engine.
public typealias CustomRuleBuilder = RuleSetBuilder
public typealias CustomRuleSet = RuleSet

extension RuleContext {
    /// Builds an evaluation context from the custom-rule worker payload.
    /// Files without source text keep their facts but have no syntax context.
    convenience init(input: CustomRuleInput) {
        self.init(
            configuration: input.configuration,
            repository: RepositorySyntax(
                fileFacts: input.files,
                files: input.files.compactMap(SourceFileContext.init)
            )
        )
    }
}

extension RuleSet {
    public func evaluate(_ input: CustomRuleInput) throws -> CustomRuleOutput {
        CustomRuleOutput(report: try evaluate(in: RuleContext(input: input)))
    }

    public func evaluateConcurrently(
        _ input: CustomRuleInput,
        maxConcurrentRuleJobs: Int? = nil
    ) async throws -> CustomRuleOutput {
        CustomRuleOutput(
            report: try await evaluateConcurrently(
                in: RuleContext(input: input),
                maxConcurrentRuleJobs: maxConcurrentRuleJobs
            )
        )
    }
}

public struct CustomRuleOutput: Equatable, Sendable, Codable {
    public let findings: [CustomRuleFinding]

    public init(findings: [CustomRuleFinding]) {
        self.findings = findings
    }

    public init(report: RuleReport) {
        self.init(findings: report.violations.map(CustomRuleFinding.init))
    }

    public static let empty = CustomRuleOutput(findings: [])

    public var architectureViolations: [ArchitectureViolation] {
        findings.map(\.architectureViolation)
    }
}

public struct CustomRuleFinding: Equatable, Sendable, Codable {
    public let ruleID: RuleID
    public let severity: Severity
    public let path: RelativeFilePath
    public let location: SourcePosition?
    public let message: String
    public let evidence: ViolationEvidence?

    public init(
        ruleID: RuleID,
        severity: Severity,
        path: RelativeFilePath,
        location: SourcePosition? = nil,
        message: String,
        evidence: ViolationEvidence? = nil
    ) {
        self.ruleID = ruleID
        self.severity = severity
        self.path = path
        self.location = location
        self.message = message
        self.evidence = evidence
    }

    public init(violation: RuleViolation) {
        self.init(
            ruleID: violation.rule.id,
            severity: violation.rule.severity,
            path: violation.path,
            location: violation.location,
            message: violation.message,
            evidence: violation.evidence
        )
    }

    public var architectureViolation: ArchitectureViolation {
        ArchitectureViolation(
            ruleID: ruleID,
            severity: severity,
            path: path,
            location: location,
            message: message,
            evidence: evidence
        )
    }
}
