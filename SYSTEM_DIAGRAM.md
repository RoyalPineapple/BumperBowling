# Bumper Bowling System Diagram

Bumper Bowling is a tiny, syntax-first architecture linter. The 0.0 system has a real adapter boundary, but Swift is the only language surface.

## Command Flow

```mermaid
flowchart TD
    CLI["bumper CLI"]

    CLI --> Init["init"]
    CLI --> Lint["lint"]
    CLI --> Scan["scan"]
    CLI --> Explain["explain"]

    Init --> SampleConfig["writes sample BumperBowling.swift"]

    Lint --> ConfigLoader["ConfigurationLoader"]
    Scan --> ConfigLoader
    Explain --> ConfigLoader

    ConfigLoader --> BuiltInConfig["Built-in 0.0 config"]

    BuiltInConfig --> Rules["ArchitectureRules"]
    BuiltInConfig --> Scanner["RepositoryScanner"]

    Scanner --> IncludeExclude["include / exclude filtering"]
    IncludeExclude --> AdapterRouter["RepositoryLanguageAdapter"]

    AdapterRouter --> SwiftAdapter["SwiftLanguageAdapter"]
    SwiftAdapter --> SwiftParser["SwiftParser + SwiftSyntax"]
    SwiftParser --> SourceFacts["SourceFileFacts"]

    SourceFacts --> RepoFacts["RepositoryFacts"]
    RepoFacts --> RuleRegistry["RuleRegistry"]

    Rules --> RuleRegistry

    RuleRegistry --> ForbiddenImport["forbidden_import"]
    RuleRegistry --> SubsystemBoundary["subsystem_boundary"]
    RuleRegistry --> DuplicateOwnership["duplicate_ownership"]
    RuleRegistry --> DependencyCycle["dependency_cycle"]
    RuleRegistry --> DomainModels["domain_models"]
    RuleRegistry --> EnumStateMachine["enum_state_machine"]

    ForbiddenImport --> Report["LintReport"]
    SubsystemBoundary --> Report
    DuplicateOwnership --> Report
    DependencyCycle --> Report
    DomainModels --> Report
    EnumStateMachine --> Report

    Report --> Console["Console output"]
    Report --> Exit["Exit nonzero only on error"]
```

## Conceptual Layers

```mermaid
flowchart LR
    DSL["Swift DSL\nBumperConfiguration"]
    Config["ArchitectureConfiguration\ninput shape"]
    TypedRules["ArchitectureRules\ntyped domain model"]
    Scanner["RepositoryScanner"]
    Adapter["SwiftLanguageAdapter"]
    Facts["SourceFileFacts\nRepositoryFacts"]
    Engine["RuleRegistry + Rules"]
    Report["LintReport"]

    DSL --> Config
    Config --> TypedRules
    Config --> Scanner
    Scanner --> Adapter
    Adapter --> Facts
    TypedRules --> Engine
    Facts --> Engine
    Engine --> Report
```

## 0.0 Boundaries

```mermaid
flowchart TD
    SwiftOnly["SourceLanguage.swift only"]
    AdapterBoundary["Adapter boundary exists"]
    Future["Other languages later"]

    SwiftOnly --> AdapterBoundary
    AdapterBoundary -. "adaptable, not implemented" .-> Future

    ConfigFile["BumperBowling.swift"]
    CLIConfig["Built-in CLI config"]

    ConfigFile -. "sample typed API only in 0.0" .-> CLIConfig
```

## Summary

The CLI loads configuration, the scanner turns Swift files into facts through the Swift adapter, the rule registry evaluates typed rules against typed facts, and the report prints plain console output. The design keeps parsing isolated from lint rules while avoiding extra language surfaces until they are real.
