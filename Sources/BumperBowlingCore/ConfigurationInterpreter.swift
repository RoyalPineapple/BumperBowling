import Foundation
import SwiftParser
import SwiftSyntax

/// The result of statically interpreting a `BumperBowling.swift` source file.
public enum ConfigurationInterpretation: Equatable, Sendable {
    /// The file stayed inside the declarative DSL subset and was evaluated
    /// without compiling or executing any configuration code.
    case configuration(ArchitectureConfiguration)
    /// The file uses Swift beyond the declarative subset and must be
    /// evaluated by the sandboxed configuration runner.
    case requiresExecution(String)
}

/// Statically interprets the declarative subset of the Bumper DSL.
///
/// The interpreter accepts exactly one shape: an optional
/// `import BumperBowlingCore`, then a single top-level
/// `let configuration = BumperConfiguration { ... }` whose contents are
/// built from known DSL constructors, string literals, and leading-dot
/// member shorthands. Everything it recognizes lowers through the same
/// functions the compiled DSL uses, so an interpreted configuration is
/// value-equal to the executed one. Anything it does not recognize is not
/// an error; it is a request to fall back to sandboxed execution.
public enum ConfigurationInterpreter {
    public static func interpret(source: String) throws -> ConfigurationInterpretation {
        do {
            let elements = try configurationElements(in: Parser.parse(source: source))
            return .configuration(BumperConfiguration(elements: elements).architectureConfiguration)
        } catch let fallback as InterpreterFallback {
            return .requiresExecution(fallback.reason)
        }
    }
}

private struct InterpreterFallback: Error {
    let reason: String
}

private func needsExecution(_ reason: String) -> InterpreterFallback {
    InterpreterFallback(reason: reason)
}

private extension ConfigurationInterpreter {
    static let coreModule = StringMatcher.exact("BumperBowlingCore")
    static let configurationBinding = StringMatcher.exact("configuration")
    static let letSpecifier = StringMatcher.exact("let")

    static func configurationElements(in file: SourceFileSyntax) throws -> [BumperConfigurationElement] {
        var configurationCall: FunctionCallExprSyntax?

        for item in file.statements {
            if let importDecl = item.item.as(ImportDeclSyntax.self) {
                guard let module = importDecl.bumper.importedModuleName, coreModule.matches(module) else {
                    let module = importDecl.bumper.importedModuleName ?? "a module bumper cannot name"
                    throw needsExecution("it imports \(module), and a plain configuration imports only BumperBowlingCore")
                }
                continue
            }

            guard let binding = configurationBinding(from: item) else {
                throw needsExecution("there is top-level Swift besides `let configuration = ...`")
            }
            guard configurationCall == nil else {
                throw needsExecution("it declares more than one configuration")
            }
            configurationCall = binding
        }

        guard let configurationCall else {
            throw needsExecution("it never says `let configuration = BumperConfiguration { ... }`")
        }

        return try elements(of: configurationCall)
    }

    static func configurationBinding(from item: CodeBlockItemSyntax) -> FunctionCallExprSyntax? {
        guard let variable = item.item.as(VariableDeclSyntax.self),
              letSpecifier.matches(variable.bindingSpecifier.text),
              variable.attributes.isEmpty,
              variable.modifiers.isEmpty,
              variable.bindings.count == 1,
              let binding = variable.bindings.first,
              binding.typeAnnotation == nil,
              binding.accessorBlock == nil,
              let name = binding.bumper.identifierName,
              configurationBinding.matches(name),
              let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
              let callee = calleeName(of: call),
              StringMatcher.exact("BumperConfiguration").matches(callee),
              call.arguments.isEmpty else {
            return nil
        }

        return call
    }

    static func elements(of configurationCall: FunctionCallExprSyntax) throws -> [BumperConfigurationElement] {
        try closureCalls(of: configurationCall, in: "BumperConfiguration").map { call in
            guard let name = calleeName(of: call), let builder = elementBuilders[name] else {
                throw needsExecution("it uses a configuration element bumper does not recognize")
            }
            return try builder(call)
        }
    }

    static let elementBuilders: [String: @Sendable (FunctionCallExprSyntax) throws -> BumperConfigurationElement] = [
        "Included": { .included(try stringList(of: $0, in: "Included")) },
        "Excluded": { .excluded(try stringList(of: $0, in: "Excluded")) },
        "Architecture": { call in
            .architecture(
                ArchitectureDefinition(
                    components: try closureCalls(of: call, in: "Architecture").map(component)
                )
            )
        },
        "Assertions": { call in
            .assertions(
                try closureCalls(of: call, in: "Assertions")
                    .map(assertion)
                    .reduce(RuleConfiguration()) { $0.merging($1) }
            )
        },
    ]

    static func component(from call: FunctionCallExprSyntax) throws -> ComponentConfiguration {
        guard let name = calleeName(of: call), StringMatcher.exact("Component").matches(name) else {
            throw needsExecution("Architecture holds something besides Component entries")
        }

        let arguments = try Arguments(of: call)
        let id = try subsystemID(of: try arguments.single())
        let elements = try closureCalls(of: call, in: "Component").map(componentElement)
        return makeComponentConfiguration(id, elements: elements)
    }

    static func componentElement(from call: FunctionCallExprSyntax) throws -> ComponentElement {
        guard let name = calleeName(of: call), let builder = componentElementBuilders[name] else {
            throw needsExecution("it uses a component element bumper does not recognize")
        }
        return try builder(call)
    }

    static let componentElementBuilders: [String: @Sendable (FunctionCallExprSyntax) throws -> ComponentElement] = [
        "Owns": { .owns(try Arguments(of: $0).strings()) },
        "Paths": { .owns(try Arguments(of: $0).strings()) },
        "Modules": { .modules(try Arguments(of: $0).strings()) },
        "MayDependOn": { .mayDependOn(try Arguments(of: $0).unlabeled().map(subsystemID)) },
        "DoesNotDependOn": { .doesNotDependOn(try Arguments(of: $0).unlabeled().map(subsystemID)) },
        "MayUse": { call in
            let arguments = try Arguments(of: call)
            return .usePolicy([
                .mayUse(
                    capabilities: Set(try arguments.unlabeled().map(capability)),
                    severity: try arguments.severity(default: .error)
                ),
            ])
        },
        "DoesNotUse": { call in
            let arguments = try Arguments(of: call)
            let severity = try arguments.severity(default: .error)
            let values = try arguments.unlabeled()
            let modules: [String]
            if values.allSatisfy(isPlainString) {
                modules = try values.map(plainString)
            } else {
                modules = try values.map(capability).flatMap(\.modules)
            }
            return .usePolicy([.doesNotUse(modules: modules, severity: severity)])
        },
        "Requires": { call in
            let arguments = try Arguments(of: call)
            let severity = try arguments.severity(default: .error)
            return .requires(
                try arguments.unlabeled().map(componentRequirement).map { requirement in
                    ComponentRequirementSetting(requirement: requirement, severity: severity, paths: [])
                }
            )
        },
        "RequiresScoped": { call in
            let arguments = try Arguments(of: call)
            let values = try arguments.unlabeled()
            guard let first = values.first else {
                throw needsExecution("RequiresScoped was called without a requirement")
            }
            return .requires([
                ComponentRequirementSetting(
                    requirement: try componentRequirement(of: first),
                    severity: try arguments.severity(default: .error),
                    paths: try values.dropFirst().map(plainString)
                ),
            ])
        },
        "Disallows": { call in
            let arguments = try Arguments(of: call)
            return .disallows([
                ImperativeDisallowanceSetting(
                    constructs: Set(try arguments.unlabeled().map(imperativeConstruct)),
                    severity: try arguments.severity(default: .error),
                    paths: try arguments.trailingStrings(startingAt: "in")
                ),
            ])
        },
        "Does": { try graphAssertion(of: $0, expectation: .does) },
        "DoesNot": { try graphAssertion(of: $0, expectation: .doesNot) },
        "Declares": { call in
            let arguments = try Arguments(of: call)
            return .graphAssertion([
                ComponentGraphAssertion(
                    expectation: .does,
                    predicate: .declare(try declarationMatchers(of: try arguments.unlabeled())),
                    severity: try arguments.severity(default: .error),
                    paths: []
                ),
            ])
        },
    ]

    static func graphAssertion(
        of call: FunctionCallExprSyntax,
        expectation: GraphPredicateExpectation
    ) throws -> ComponentElement {
        let arguments = try Arguments(of: call)
        let predicateCall = try arguments.single()
        guard let inner = predicateCall.as(FunctionCallExprSyntax.self),
              let name = calleeName(of: inner),
              StringMatcher.exact("Declare").matches(name) else {
            throw needsExecution("it uses a graph predicate bumper cannot read without running it")
        }

        return .graphAssertion([
            ComponentGraphAssertion(
                expectation: expectation,
                predicate: .declare(try declarationMatchers(of: try Arguments(of: inner).unlabeled())),
                severity: try arguments.severity(default: .error),
                paths: []
            ),
        ])
    }

    static func assertion(from call: FunctionCallExprSyntax) throws -> RuleConfiguration {
        guard let name = calleeName(of: call), let builder = assertionBuilders[name] else {
            throw needsExecution("it uses an assertion bumper does not recognize")
        }
        return try builder(call)
    }

    static let assertionBuilders: [String: @Sendable (FunctionCallExprSyntax) throws -> RuleConfiguration] = [
        "DependencyBoundaries": { DependencyBoundaries(try Arguments(of: $0).singleSeverity()) },
        "SingleOwner": { SingleOwner(try Arguments(of: $0).singleSeverity()) },
        "AcyclicDeclaredDependencies": { AcyclicDeclaredDependencies(try Arguments(of: $0).singleSeverity()) },
        "NoDirectStringMatching": { call in
            let arguments = try Arguments(of: call)
            return NoDirectStringMatching(
                try severity(of: try arguments.single()),
                paths: try stringArray(of: try arguments.required("paths")),
                except: try arguments.optional("except").map(stringArray) ?? []
            )
        },
    ]
}

// MARK: - Leaf value evaluation

private extension ConfigurationInterpreter {
    static let subsystemIDs: [String: SubsystemID] = [.core, .cli, .app, .ui, .tests]
        .reduce(into: [:]) { $0[$1.rawValue] = $1 }

    static let capabilities: [String: Capability] = Capability.allCases
        .reduce(into: [:]) { $0[String(describing: $1)] = $1 }

    static let componentRequirements: [String: ComponentRequirement] = [
        "noAnyStoredProperties": .noAnyStoredProperties,
        "noBroadExistentialStoredProperties": .noBroadExistentialStoredProperties,
        "noRawStringStoredProperties": .noRawStringStoredProperties,
        "noStoredProperties": .noStoredProperties,
        "immutableStoredState": .immutableStoredState,
        "enumStateMachine": .enumStateMachine,
        "explicitDomainSurfaces": .explicitDomainSurfaces,
        "typedIdentity": .typedIdentity,
        "computedState": .computedState,
        "functionalCore": .functionalCore,
        "swiftBasics": .swiftBasics,
        "parserStateMachine": .parserStateMachine,
        "pureDomain": .pureDomain,
    ]

    static func subsystemID(of expression: ExprSyntax) throws -> SubsystemID {
        guard let id = subsystemIDs[try memberName(of: expression)] else {
            throw needsExecution("it names a subsystem bumper does not know")
        }
        return id
    }

    static func capability(of expression: ExprSyntax) throws -> Capability {
        guard let capability = capabilities[try memberName(of: expression)] else {
            throw needsExecution("it names a capability bumper does not know")
        }
        return capability
    }

    static func componentRequirement(of expression: ExprSyntax) throws -> ComponentRequirement {
        guard let requirement = componentRequirements[try memberName(of: expression)] else {
            throw needsExecution("it names a requirement bumper does not know")
        }
        return requirement
    }

    static func imperativeConstruct(of expression: ExprSyntax) throws -> ImperativeConstruct {
        guard let construct = ImperativeConstruct(rawValue: try memberName(of: expression)) else {
            throw needsExecution("it names an imperative construct bumper does not know")
        }
        return construct
    }

    static func severity(of expression: ExprSyntax) throws -> Severity {
        guard let severity = Severity(rawValue: try memberName(of: expression)) else {
            throw needsExecution("it names a severity bumper does not know")
        }
        return severity
    }

    static func declarationMatchers(of expressions: [ExprSyntax]) throws -> Set<StringMatcher> {
        Set(
            try expressions.map { expression in
                if isPlainString(expression) {
                    return StringMatcher.exact(try DeclarationName(try plainString(of: expression)).rawValue)
                }
                return try stringMatcher(of: expression)
            }
        )
    }

    static func stringMatcher(of expression: ExprSyntax) throws -> StringMatcher {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.base == nil,
              let mode = StringMatcher.Mode(rawValue: member.declName.baseName.text),
              call.arguments.count == 1,
              let argument = call.arguments.first,
              argument.label == nil else {
            throw needsExecution("it uses a string matcher bumper cannot read without running it")
        }

        let pattern = try plainString(of: argument.expression)
        guard !pattern.isEmpty else {
            throw needsExecution("a string matcher was given an empty pattern")
        }
        return StringMatcher(mode: mode, pattern: pattern)
    }

    static func memberName(of expression: ExprSyntax) throws -> String {
        guard let member = expression.as(MemberAccessExprSyntax.self), member.base == nil else {
            throw needsExecution("an argument is not the leading-dot shorthand bumper expects")
        }
        return member.declName.baseName.text
    }

    static func isPlainString(_ expression: ExprSyntax) -> Bool {
        (try? plainString(of: expression)) != nil
    }

    static func plainString(of expression: ExprSyntax) throws -> String {
        guard let literal = expression.as(StringLiteralExprSyntax.self),
              literal.segments.count == literal.segments.compactMap({ $0.as(StringSegmentSyntax.self) }).count else {
            throw needsExecution("a string is not a plain literal, and interpolation means running code")
        }

        return literal.segments
            .compactMap { $0.as(StringSegmentSyntax.self)?.content.text }
            .joined()
    }

    static func stringArray(of expression: ExprSyntax) throws -> [String] {
        guard let array = expression.as(ArrayExprSyntax.self) else {
            throw needsExecution("an argument is not a plain array of strings")
        }
        return try array.elements.map { try plainString(of: $0.expression) }
    }

    static func stringList(of call: FunctionCallExprSyntax, in context: String) throws -> [String] {
        guard call.arguments.isEmpty else {
            throw needsExecution("arguments were passed to \(context), which takes none")
        }
        return try closureStatements(of: call, in: context).map { statement in
            guard let expression = statement.item.as(ExprSyntax.self) else {
                throw needsExecution("there are statements inside \(context) bumper cannot read as values")
            }
            return try plainString(of: expression)
        }
    }

    static func closureCalls(
        of call: FunctionCallExprSyntax,
        in context: String
    ) throws -> [FunctionCallExprSyntax] {
        try closureStatements(of: call, in: context).map { statement in
            guard let inner = statement.item.as(FunctionCallExprSyntax.self) else {
                throw needsExecution("there are statements inside \(context) bumper does not recognize")
            }
            return inner
        }
    }

    static func closureStatements(
        of call: FunctionCallExprSyntax,
        in context: String
    ) throws -> [CodeBlockItemSyntax] {
        guard let closure = call.trailingClosure else {
            throw needsExecution("the trailing closure on \(context) is missing")
        }
        guard call.additionalTrailingClosures.isEmpty, closure.signature == nil else {
            throw needsExecution("the closure on \(context) is fancier than bumper can read")
        }
        return Array(closure.statements)
    }

    static func calleeName(of call: FunctionCallExprSyntax) -> String? {
        call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
    }
}

// MARK: - Call arguments

private struct Arguments {
    private let entries: [(label: String?, expression: ExprSyntax)]

    init(of call: FunctionCallExprSyntax) throws {
        self.entries = call.arguments.map { argument in
            (argument.label?.text, argument.expression)
        }
    }

    /// Unlabeled arguments before any labeled argument; the leading variadic
    /// parameter of every DSL constructor.
    func unlabeled() throws -> [ExprSyntax] {
        Array(entries.prefix(while: { $0.label == nil }).map(\.expression))
    }

    func single() throws -> ExprSyntax {
        let values = try unlabeled()
        guard values.count == 1, entries.count == values.count + labeled().count else {
            throw needsExecution("arguments were passed that bumper cannot read without running them")
        }
        return values[0]
    }

    func singleSeverity() throws -> Severity {
        try ConfigurationInterpreter.severity(of: try single())
    }

    func severity(default defaultSeverity: Severity) throws -> Severity {
        guard let expression = try optional("severity") else {
            return defaultSeverity
        }
        return try ConfigurationInterpreter.severity(of: expression)
    }

    func strings() throws -> [String] {
        guard entries.allSatisfy({ $0.label == nil }) else {
            throw needsExecution("labeled arguments were passed that bumper does not expect")
        }
        return try entries.map { try ConfigurationInterpreter.plainString(of: $0.expression) }
    }

    func required(_ label: String) throws -> ExprSyntax {
        guard let expression = try optional(label) else {
            throw needsExecution("the \(label) argument is missing")
        }
        return expression
    }

    func optional(_ label: String) throws -> ExprSyntax? {
        let matcher = StringMatcher.exact(label)
        return entries.first { entry in
            guard let entryLabel = entry.label else {
                return false
            }
            return matcher.matches(entryLabel)
        }?.expression
    }

    /// A labeled variadic tail such as `in: "a", "b"`: the labeled argument
    /// plus every unlabeled argument that follows it.
    func trailingStrings(startingAt label: String) throws -> [String] {
        let matcher = StringMatcher.exact(label)
        guard let start = entries.firstIndex(where: { entry in
            guard let entryLabel = entry.label else {
                return false
            }
            return matcher.matches(entryLabel)
        }) else {
            return []
        }

        let tail = entries[start...].enumerated().prefix { offset, entry in
            offset == 0 || entry.label == nil
        }
        return try tail.map { try ConfigurationInterpreter.plainString(of: $0.element.expression) }
    }

    private func labeled() -> [(label: String?, expression: ExprSyntax)] {
        entries.filter { $0.label != nil }
    }
}
