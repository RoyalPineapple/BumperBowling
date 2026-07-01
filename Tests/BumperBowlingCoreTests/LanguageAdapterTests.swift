import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("LanguageAdapter")
struct LanguageAdapterTests {
    @Test
    func swiftAdapterProducesLanguageNeutralFacts() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let file = root.appendingPathComponent("Sources/Core/Thing.swift")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        import Foundation

        public struct Thing {}
        """.write(to: file, atomically: true, encoding: .utf8)

        let adapter = SwiftLanguageAdapter()
        let facts = try await adapter.parse(
            SourceFileInput(
                url: file,
                relativePath: try RelativeFilePath("Sources/Core/Thing.swift"),
                subsystem: try SubsystemID("core")
            )
        )

        #expect(facts.language == .swift)
        #expect(facts.imports == [try ModuleName("Foundation")])
        #expect(facts.publicDeclarations.contains(PublicDeclaration(kind: .struct, name: try DeclarationName("Thing"))))
    }
}
