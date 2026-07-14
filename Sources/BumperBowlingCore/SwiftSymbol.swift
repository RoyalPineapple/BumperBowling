import Foundation

/// A typed source symbol. Bumper cannot import the target project, so
/// symbols originate as text; the phantom `Kind` quarantines that text and
/// keeps operations on the correct symbol category.
public struct SwiftSymbol<Kind>: Hashable, Sendable, Codable, CustomStringConvertible {
    public let name: String

    public init(_ name: String) {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            preconditionFailure("Swift symbols cannot be empty.")
        }
        self.name = normalized
    }

    public var description: String {
        name
    }
}

extension SwiftSymbol: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

public enum NominalSymbolKind: Sendable {}
public enum FunctionSymbolKind: Sendable {}
public enum PropertySymbolKind: Sendable {}
public enum EnumCaseSymbolKind: Sendable {}

public typealias NominalSymbol = SwiftSymbol<NominalSymbolKind>
public typealias FunctionSymbol = SwiftSymbol<FunctionSymbolKind>
public typealias PropertySymbol = SwiftSymbol<PropertySymbolKind>
public typealias EnumCaseSymbol = SwiftSymbol<EnumCaseSymbolKind>
