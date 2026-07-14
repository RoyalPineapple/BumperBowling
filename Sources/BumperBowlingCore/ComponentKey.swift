import Foundation

/// A project-owned component enum. The enum is authoring syntax; the
/// architecture graph stores `ComponentID`.
public protocol ComponentKey:
    CaseIterable,
    Hashable,
    RawRepresentable,
    Sendable
where RawValue == String {}

extension ComponentKey {
    /// Raw values validate at the authoring boundary; an unrepresentable
    /// component key is a configuration bug, not a silent empty scope.
    var componentID: ComponentID {
        guard let id = try? ComponentID(rawValue) else {
            preconditionFailure("Component key '\(rawValue)' is not a valid component ID.")
        }
        return id
    }
}
