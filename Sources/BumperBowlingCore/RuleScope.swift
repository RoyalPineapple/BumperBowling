import Foundation

/// Which files a rule evaluates over. Built-in scopes are conveniences over
/// one open predicate initializer, not a closed taxonomy.
public struct RuleScope: Sendable {
    private let predicate: @Sendable (RelativeFilePath, ComponentID) -> Bool

    public init(_ predicate: @escaping @Sendable (RelativeFilePath, ComponentID) -> Bool) {
        self.predicate = predicate
    }

    public static let repository = RuleScope { _, _ in true }

    // ponytail: production == not under Tests/; a configured production-root
    // scope can replace this when a repository needs a different split.
    public static let productionSources = RuleScope { path, _ in
        !StringMatcher.prefix("Tests/").matches(path)
    }

    public static func component(_ component: ComponentID) -> RuleScope {
        RuleScope { _, fileComponent in
            fileComponent == component
        }
    }

    public static func under(_ path: RelativePathPrefix) -> RuleScope {
        RuleScope { filePath, _ in
            path.contains(filePath)
        }
    }

    public static func files(_ paths: Set<RelativeFilePath>) -> RuleScope {
        RuleScope { filePath, _ in
            paths.contains(filePath)
        }
    }

    public func union(_ other: RuleScope) -> RuleScope {
        RuleScope { path, component in
            self.includes(path: path, component: component)
                || other.includes(path: path, component: component)
        }
    }

    public func intersecting(_ other: RuleScope) -> RuleScope {
        RuleScope { path, component in
            self.includes(path: path, component: component)
                && other.includes(path: path, component: component)
        }
    }

    public func excluding(_ other: RuleScope) -> RuleScope {
        RuleScope { path, component in
            self.includes(path: path, component: component)
                && !other.includes(path: path, component: component)
        }
    }

    public func includes(path: RelativeFilePath, component: ComponentID) -> Bool {
        predicate(path, component)
    }

    func includes(_ file: SourceFileContext) -> Bool {
        includes(path: file.path, component: file.component)
    }
}
