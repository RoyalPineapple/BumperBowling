extension Array where Element == RuleConfiguration {
    func combined() -> RuleConfiguration {
        reduce(RuleConfiguration()) { partialResult, configuration in
            partialResult.merging(configuration)
        }
    }
}
extension RuleConfiguration {
    func merging(_ other: RuleConfiguration) -> RuleConfiguration {
        RuleConfiguration(
            forbiddenImports: forbiddenImports + other.forbiddenImports,
            subsystemBoundary: other.subsystemBoundary.isConfigured ? other.subsystemBoundary : subsystemBoundary,
            duplicateOwnership: other.duplicateOwnership.isConfigured ? other.duplicateOwnership : duplicateOwnership,
            declaredDependencyCycle: other.declaredDependencyCycle.isConfigured
                ? other.declaredDependencyCycle
                : declaredDependencyCycle,
            storedProperties: storedProperties.merging(other.storedProperties),
            syntaxConstructs: syntaxConstructs.merging(other.syntaxConstructs),
            syntaxKinds: syntaxKinds.merging(other.syntaxKinds),
            publicDeclarations: publicDeclarations.merging(other.publicDeclarations),
            enumStateMachine: enumStateMachine.merging(other.enumStateMachine)
        )
    }
}

private extension StoredPropertyRuleConfiguration {
    func merging(_ other: StoredPropertyRuleConfiguration) -> StoredPropertyRuleConfiguration {
        StoredPropertyRuleConfiguration(
            severity: severity.merging(other.severity),
            paths: Array(Set(paths + other.paths)).sorted(),
            excludedPaths: Array(Set(excludedPaths + other.excludedPaths)).sorted(),
            disallowances: disallowances.union(other.disallowances)
        )
    }
}

private extension SyntaxConstructRuleConfiguration {
    func merging(_ other: SyntaxConstructRuleConfiguration) -> SyntaxConstructRuleConfiguration {
        SyntaxConstructRuleConfiguration(
            severity: severity.merging(other.severity),
            paths: Array(Set(paths + other.paths)).sorted(),
            excludedPaths: Array(Set(excludedPaths + other.excludedPaths)).sorted(),
            disallowedConstructs: disallowedConstructs.union(other.disallowedConstructs)
        )
    }
}

private extension SyntaxKindRuleConfiguration {
    func merging(_ other: SyntaxKindRuleConfiguration) -> SyntaxKindRuleConfiguration {
        SyntaxKindRuleConfiguration(
            severity: severity.merging(other.severity),
            paths: Array(Set(paths + other.paths)).sorted(),
            requiredKinds: requiredKinds.union(other.requiredKinds),
            disallowedKinds: disallowedKinds.union(other.disallowedKinds)
        )
    }
}

private extension PublicDeclarationRuleConfiguration {
    func merging(_ other: PublicDeclarationRuleConfiguration) -> PublicDeclarationRuleConfiguration {
        PublicDeclarationRuleConfiguration(
            severity: severity.merging(other.severity),
            paths: Array(Set(paths + other.paths)).sorted(),
            requiredNames: requiredNames.union(other.requiredNames),
            disallowedNames: disallowedNames.union(other.disallowedNames)
        )
    }
}

private extension PathRuleConfiguration {
    func merging(_ other: PathRuleConfiguration) -> PathRuleConfiguration {
        PathRuleConfiguration(
            severity: severity.merging(other.severity),
            paths: Array(Set(paths + other.paths)).sorted()
        )
    }
}

private extension Severity {
    var isConfigured: Bool {
        self != .off
    }
}

private extension StoredPropertyRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty || !disallowances.isEmpty
    }
}

private extension SyntaxConstructRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty || !excludedPaths.isEmpty || !disallowedConstructs.isEmpty
    }
}

private extension SyntaxKindRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty || !requiredKinds.isEmpty || !disallowedKinds.isEmpty
    }
}

private extension PublicDeclarationRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty || !requiredNames.isEmpty || !disallowedNames.isEmpty
    }
}

private extension PathRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty
    }
}
