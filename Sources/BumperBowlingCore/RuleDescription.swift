import Foundation

public struct RuleDescription: Equatable, Sendable {
    public let id: RuleID
    public let name: String
    public let description: String
    public let nonTriggeringExamples: [RuleExample]
    public let triggeringExamples: [RuleExample]

    public init(
        id: RuleID,
        name: String,
        description: String,
        nonTriggeringExamples: [RuleExample] = [],
        triggeringExamples: [RuleExample] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.nonTriggeringExamples = nonTriggeringExamples
        self.triggeringExamples = triggeringExamples
    }
}

public struct RuleExample: Equatable, Sendable {
    public let code: String
    public let path: RelativeFilePath
    public let subsystem: SubsystemID

    public init(code: String, path: RelativeFilePath, subsystem: SubsystemID) {
        self.code = code
        self.path = path
        self.subsystem = subsystem
    }
}

public extension ArchitectureRule {
    var ruleDescription: RuleDescription {
        switch self {
        case .forbiddenImport:
            RuleDescription(
                id: id,
                name: "Forbidden Import",
                description: description,
                nonTriggeringExamples: [
                    RuleExample(
                        code: "import Foundation\n\npublic struct Thing {}\n",
                        path: knownPath("Sources/BumperBowlingCore/Thing.swift"),
                        subsystem: knownSubsystem("core")
                    ),
                ],
                triggeringExamples: [
                    RuleExample(
                        code: "↓import XCTest\n\npublic struct Thing {}\n",
                        path: knownPath("Sources/BumperBowlingCore/Thing.swift"),
                        subsystem: knownSubsystem("core")
                    ),
                ]
            )
        case .storedProperties:
            RuleDescription(
                id: id,
                name: "Stored Properties",
                description: description,
                nonTriggeringExamples: [
                    RuleExample(
                        code: "public struct Model {\n    let id: Identifier\n}\n",
                        path: knownPath("Sources/BumperBowlingCore/Model.swift"),
                        subsystem: knownSubsystem("core")
                    ),
                ],
                triggeringExamples: [
                    RuleExample(
                        code: "public struct Model {\n    ↓var id: Identifier\n}\n",
                        path: knownPath("Sources/BumperBowlingCore/Model.swift"),
                        subsystem: knownSubsystem("core")
                    ),
                ]
            )
        case .syntaxConstructs:
            RuleDescription(
                id: id,
                name: "Syntax Constructs",
                description: description,
                nonTriggeringExamples: [
                    RuleExample(
                        code: "public func reduce(_ value: Int) -> Int {\n    value + 1\n}\n",
                        path: knownPath("Sources/BumperBowlingCore/Reducer.swift"),
                        subsystem: knownSubsystem("core")
                    ),
                ],
                triggeringExamples: [
                    RuleExample(
                        code: "public func reduce(_ value: Int) -> Int {\n    ↓var next = value\n    next += 1\n    return next\n}\n",
                        path: knownPath("Sources/BumperBowlingCore/Reducer.swift"),
                        subsystem: knownSubsystem("core")
                    ),
                ]
            )
        case .syntaxKinds:
            RuleDescription(
                id: id,
                name: "Syntax Kinds",
                description: description
            )
        case .enumStateMachine:
            RuleDescription(
                id: id,
                name: "Enum State Machine",
                description: description,
                nonTriggeringExamples: [
                    RuleExample(
                        code: "enum ParserState { case scanning }\npublic struct ThingParser {}\n",
                        path: knownPath("Sources/BumperBowlingCore/ThingParser.swift"),
                        subsystem: knownSubsystem("core")
                    ),
                ],
                triggeringExamples: [
                    RuleExample(
                        code: "↓public struct ThingParser {}\n",
                        path: knownPath("Sources/BumperBowlingCore/ThingParser.swift"),
                        subsystem: knownSubsystem("core")
                    ),
                ]
            )
        case .subsystemBoundary:
            RuleDescription(id: id, name: "Subsystem Boundary", description: description)
        case .duplicateOwnership:
            RuleDescription(id: id, name: "Duplicate Ownership", description: description)
        case .declaredDependencyCycle:
            RuleDescription(id: id, name: "Declared Dependency Cycle", description: description)
        }
    }
}

private func knownPath(_ rawValue: String) -> RelativeFilePath {
    guard let path = try? RelativeFilePath(rawValue) else {
        preconditionFailure("Invalid bundled rule example path: \(rawValue)")
    }
    return path
}

private func knownSubsystem(_ rawValue: String) -> SubsystemID {
    guard let subsystem = try? SubsystemID(rawValue) else {
        preconditionFailure("Invalid bundled rule example subsystem: \(rawValue)")
    }
    return subsystem
}
