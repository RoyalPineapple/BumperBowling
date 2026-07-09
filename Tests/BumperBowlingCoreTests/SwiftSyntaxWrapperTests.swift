import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("SwiftSyntax wrapper")
struct SwiftSyntaxWrapperTests {
    @Test
    func parserProducesSourceFileFacts() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let file = root.appendingPathComponent("Sources/Core/Thing.swift")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let source = """
        import Foundation

        public struct Thing {}
        """
        try source.write(to: file, atomically: true, encoding: .utf8)

        let nodes = try SwiftFileParser().parseFile(
            at: file,
            relativePath: try RelativeFilePath("Sources/Core/Thing.swift"),
            component: try ComponentID("core")
        )

        #expect(nodes.imports == [try ModuleName("Foundation")])
        #expect(nodes.source == source)
        #expect(nodes.publicDeclarations.contains {
            $0.kind == .struct
                && $0.name == (try? DeclarationName("Thing"))
                && $0.location != nil
        })
    }
}
