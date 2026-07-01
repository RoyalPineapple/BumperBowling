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
}
