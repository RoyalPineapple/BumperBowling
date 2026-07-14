import Foundation

/// Which files a rule evaluates over. Built-in scopes are conveniences over
/// one open predicate initializer, not a closed taxonomy.
public struct RuleScope: Sendable {
    private let predicate: @Sendable (SourceFileDescriptor) -> Bool

    public init(_ includes: @escaping @Sendable (SourceFileDescriptor) -> Bool) {
        self.predicate = includes
    }

    public static let repository = RuleScope { _ in true }

    // ponytail: production == not under Tests/; a configured production-root
    // scope can replace this when a repository needs a different split.
    public static let productionSources = RuleScope { file in
        !StringMatcher.prefix("Tests/").matches(file.path)
    }

    public static func component<Key: ComponentKey>(_ component: Key) -> RuleScope {
        self.component(component.componentID)
    }

    public static func component(_ component: ComponentID) -> RuleScope {
        RuleScope { file in
            file.component == component
        }
    }

    public static func under(_ path: RelativePathPrefix) -> RuleScope {
        RuleScope { file in
            path.contains(file.path)
        }
    }

    public static func files(_ paths: Set<RelativeFilePath>) -> RuleScope {
        RuleScope { file in
            paths.contains(file.path)
        }
    }

    public func union(_ other: RuleScope) -> RuleScope {
        RuleScope { file in
            self.includes(file) || other.includes(file)
        }
    }

    public func intersecting(_ other: RuleScope) -> RuleScope {
        RuleScope { file in
            self.includes(file) && other.includes(file)
        }
    }

    public func excluding(_ other: RuleScope) -> RuleScope {
        RuleScope { file in
            self.includes(file) && !other.includes(file)
        }
    }

    public func includes(_ file: SourceFileDescriptor) -> Bool {
        predicate(file)
    }

    func includes(_ file: SourceFileContext) -> Bool {
        includes(file.descriptor)
    }
}
