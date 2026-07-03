import Testing
import SwiftSyntax
@testable import BumperBowlingCore

@Suite("SwiftFileParser")
struct SwiftFileParserTests {
    @Test
    func parsesImportsAndPublicDeclarations() throws {
        let source = """
        import Foundation
        @testable import Playback

        @MainActor
        public final class Recorder {
            public var isRecording: Bool

            public func start() {}
            private func stop() {}
        }

        struct InternalThing {}
        """

        let summary = SwiftFileParser().parse(source)
        let mainActor = try AttributeName("MainActor")

        #expect(summary.imports == [try ModuleName("Foundation"), try ModuleName("Playback")])
        #expect(summary.publicDeclarations.contains {
            $0.kind == .class
                && $0.name == (try? DeclarationName("Recorder"))
                && $0.attributes == [mainActor]
                && $0.location != nil
        })
        #expect(summary.publicDeclarations.contains {
            $0.kind == .variable
                && $0.name == (try? DeclarationName("isRecording"))
                && $0.attributes.isEmpty
                && $0.location != nil
        })
        #expect(summary.publicDeclarations.contains {
            $0.kind == .function
                && $0.name == (try? DeclarationName("start"))
                && $0.attributes.isEmpty
                && $0.location != nil
        })
        #expect(!summary.publicDeclarations.contains { $0.name == (try? DeclarationName("stop")) })
    }

    @Test
    func parsesImperativeConstructs() {
        let source = """
        func consume(_ values: inout [Int]) {}

        struct Counter {
            mutating func increment(_ values: inout [Int]) {
                var total = 0
                for value in values {
                    total = total + value
                }
                consume(&values)
                values.append(total)
            }
        }
        """

        let summary = SwiftFileParser().parse(source)

        #expect(summary.imperativeConstructs.contains(.mutatingDeclaration))
        #expect(summary.imperativeConstructs.contains(.mutableBinding))
        #expect(summary.imperativeConstructs.contains(.loop))
        #expect(summary.imperativeConstructs.contains(.assignment))
        #expect(summary.imperativeConstructs.contains(.inoutExpression))
    }

    @Test
    func parsesDirectStringMatchingConstructs() {
        let source = """
        struct Status {
            let rawValue: String

            func isReady(_ name: String) -> Bool {
                rawValue == "ready" || name.hasSuffix("State") || name.contains("Reducer")
            }

            func hasID(_ ids: [Int]) -> Bool {
                ids.contains(42)
            }
        }
        """

        let summary = SwiftFileParser().parse(source)

        #expect(summary.imperativeConstructs.contains(.directStringMatch))
    }

    @Test
    func parsesOwnerAwareTypeFacts() throws {
        let source = """
        @MainActor
        public struct User {
            let id: UserID
        }

        extension User: Identifiable {}
        """

        let summary = SwiftFileParser().parse(source)
        let userName = try TypeName("User")
        let userIDName = try TypeName("UserID")
        let identifiableName = try TypeName("Identifiable")
        let user = try #require(summary.nominalTypes.first { $0.name == (try? TypeName("User")) })
        let id = try #require(summary.storedProperties.first { $0.name == (try? DeclarationName("id")) })
        let userExtension = try #require(summary.extensionDeclarations.first)

        #expect(user.kind == .struct)
        #expect(user.access == .public)
        #expect(user.attributes == [try AttributeName("MainActor")])
        #expect(id.owner == userName)
        #expect(id.type == userIDName)
        #expect(userExtension.extendedType == userName)
        #expect(userExtension.inheritedTypes == [identifiableName])
    }

    @Test
    func recordsFullSwiftSyntaxFactCatalog() {
        let source = """
        import Foundation

        @MainActor
        struct Model {
            let id: String

            func render() -> String {
                "id: \\(id)"
            }
        }
        """

        let summary = SwiftFileParser().parse(source)

        #expect(summary.syntaxFacts.nodeKinds.contains(.sourceFile))
        #expect(summary.syntaxFacts.nodeKinds.contains(.importDecl))
        #expect(summary.syntaxFacts.nodeKinds.contains(.structDecl))
        #expect(summary.syntaxFacts.nodeKinds.contains(.attribute))
        #expect(summary.syntaxFacts.nodeKinds.contains(.identifierType))
        #expect(summary.syntaxFacts.nodeKinds.contains(.stringLiteralExpr))
        #expect(summary.syntaxFacts.facts.contains { $0.family == .declaration && $0.nodeKind == .structDecl })
        #expect(summary.syntaxFacts.facts.contains { $0.family == .attribute && $0.nodeKind == .attribute })
        #expect(summary.syntaxFacts.facts.contains { $0.family == .literal && $0.nodeKind == .stringLiteralExpr })
    }

    @Test
    func recordsDeterministicPositionsForObservedFacts() throws {
        let source = """
        import Foundation

        struct Model {
            var name: String

            mutating func rename(to value: String) {
                name = value
            }
        }
        """

        let summary = SwiftFileParser().parse(source)
        let property = try #require(summary.storedProperties.first { $0.name == (try? DeclarationName("name")) })
        let assignment = try #require(summary.observedImperativeConstructs.first { $0.construct == .assignment })
        let structFact = try #require(summary.syntaxFacts.facts.first { $0.nodeKind == .structDecl })

        #expect(property.location == SourcePosition(line: 4, column: 5))
        #expect(assignment.location == SourcePosition(line: 7, column: 14))
        #expect(structFact.location == SourcePosition(line: 3, column: 1))
    }
}
