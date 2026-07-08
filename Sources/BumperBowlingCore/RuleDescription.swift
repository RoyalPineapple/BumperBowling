public struct RuleDescription: Equatable, Sendable {
    public let id: RuleID
    public let name: String
    public let description: String

    public init(id: RuleID, name: String, description: String) {
        self.id = id
        self.name = name
        self.description = description
    }
}

public extension ArchitectureRule {
    var ruleDescription: RuleDescription {
        switch self {
        case .forbiddenImport:
            RuleDescription(
                id: id,
                name: "Forbidden Import",
                description: description
            )
        case .storedProperties:
            RuleDescription(
                id: id,
                name: "Stored Properties",
                description: description
            )
        case .syntaxConstructs:
            RuleDescription(
                id: id,
                name: "Syntax Constructs",
                description: description
            )
        case .syntaxKinds:
            RuleDescription(
                id: id,
                name: "Syntax Kinds",
                description: description
            )
        case .syntaxNodes:
            RuleDescription(
                id: id,
                name: "Syntax Nodes",
                description: description
            )
        case .publicDeclarations:
            RuleDescription(
                id: id,
                name: "Public Declarations",
                description: description
            )
        case .enumStateMachine:
            RuleDescription(
                id: id,
                name: "Enum State Machine",
                description: description
            )
        case .componentBoundary:
            RuleDescription(id: id, name: "Component Boundary", description: description)
        case .duplicateOwnership:
            RuleDescription(id: id, name: "Duplicate Ownership", description: description)
        case .declaredDependencyCycle:
            RuleDescription(id: id, name: "Declared Dependency Cycle", description: description)
        }
    }
}
