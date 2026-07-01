import Testing
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

        #expect(summary.imports == [try ModuleName("Foundation"), try ModuleName("Playback")])
        #expect(summary.publicDeclarations.contains(PublicDeclaration(kind: .class, name: try DeclarationName("Recorder"), attributes: [try AttributeName("MainActor")])))
        #expect(summary.publicDeclarations.contains(PublicDeclaration(kind: .variable, name: try DeclarationName("isRecording"), attributes: [])))
        #expect(summary.publicDeclarations.contains(PublicDeclaration(kind: .function, name: try DeclarationName("start"), attributes: [])))
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
}
