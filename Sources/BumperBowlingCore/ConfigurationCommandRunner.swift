import Foundation

public enum ConfigurationCommand: Sendable {
    case lint
    case scan
    case snapshot
    case explain(URL)

    var rawValue: String {
        switch self {
        case .lint:
            "lint"
        case .scan:
            "scan"
        case .snapshot:
            "snapshot"
        case .explain:
            "explain"
        }
    }

    var arguments: [String] {
        switch self {
        case .lint, .scan, .snapshot:
            []
        case .explain(let path):
            [path.path]
        }
    }
}

public extension ConfigurationLoader {
    static func runLint(root: URL) throws -> LintReport {
        let output = try runConfigurationCommand(.lint, root: root)
        guard !output.isEmpty else {
            throw BumperError.configurationOutputMalformed("empty lint payload")
        }
        return try JSONDecoder().decode(LintReport.self, from: Data(output.utf8))
    }

    static func runStringCommand(_ command: ConfigurationCommand, root: URL) throws -> String {
        try runConfigurationCommand(command, root: root)
    }
}

private extension ConfigurationLoader {
    static let outputBeginMarker = "__BUMPER_OUTPUT_BEGIN__"
    static let outputEndMarker = "__BUMPER_OUTPUT_END__"

    static func runConfigurationCommand(_ command: ConfigurationCommand, root: URL) throws -> String {
        let root = root.standardizedFileURL
        let configurationURL = root.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            throw BumperError.configurationMissing(configurationURL.path)
        }

        let packageRoot = try bumperPackageRoot()
        let workingDirectory = try makeTemporaryPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: packageRoot
        )
        defer {
            try? FileManager.default.removeItem(at: workingDirectory)
        }

        let stderrURL = workingDirectory.appendingPathComponent("stderr.txt")
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stderrHandle.close()
        }

        let stdout = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swift",
            "run",
            "--package-path",
            workingDirectory.path,
            "BumperConfigurationRunner",
            root.path,
            command.rawValue,
        ] + command.arguments
        process.standardOutput = stdout
        process.standardError = stderrHandle

        try process.run()
        process.waitUntilExit()

        let stdoutText = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderrText = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""

        guard process.terminationStatus == 0 else {
            throw BumperError.configurationExecutionFailed(
                configurationURL.path,
                stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return try extractPayload(from: stdoutText)
    }

    static func makeTemporaryPackage(
        configurationURL: URL,
        bumperPackageRoot: URL
    ) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BumperConfigurationLoader-\(UUID().uuidString)")
        let sources = root.appendingPathComponent("Sources/BumperConfigurationRunner")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)

        try packageManifest(bumperPackageRoot: bumperPackageRoot)
            .write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try FileManager.default.copyItem(
            at: configurationURL,
            to: sources.appendingPathComponent("UserConfiguration.swift")
        )
        try runnerSource.write(
            to: sources.appendingPathComponent("main.swift"),
            atomically: true,
            encoding: .utf8
        )

        return root
    }

    static func bumperPackageRoot() throws -> URL {
        if let environmentPath = ProcessInfo.processInfo.environment["BUMPER_PACKAGE_PATH"] {
            let root = URL(fileURLWithPath: environmentPath).standardizedFileURL
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else {
                throw BumperError.configurationPackageUnavailable(root.path)
            }
            return root
        }

        let sourcePath = URL(fileURLWithPath: #filePath)
        let root = sourcePath
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else {
            throw BumperError.configurationPackageUnavailable(root.path)
        }
        return root
    }

    static func packageManifest(bumperPackageRoot: URL) -> String {
        """
        // swift-tools-version: 6.2
        import PackageDescription

        let package = Package(
            name: "BumperConfigurationLoader",
            platforms: [
                .macOS(.v15),
            ],
            dependencies: [
                .package(path: \(swiftStringLiteral(bumperPackageRoot.path))),
            ],
            targets: [
                .executableTarget(
                    name: "BumperConfigurationRunner",
                    dependencies: [
                        .product(name: "BumperBowlingCore", package: "BumperBowling"),
                    ],
                    swiftSettings: [
                        .enableUpcomingFeature("StrictConcurrency"),
                        .enableUpcomingFeature("InferSendableFromCaptures"),
                    ]
                ),
            ]
        )
        """
    }

    static var runnerSource: String {
        """
        import BumperBowlingCore
        import Dispatch
        import Foundation

        func writePayload(_ payload: String) {
            let output = "\(outputBeginMarker)\\n" + payload + "\\n\(outputEndMarker)\\n"
            FileHandle.standardOutput.write(Data(output.utf8))
        }

        func encodedReport(_ report: LintReport) throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return String(data: try encoder.encode(report), encoding: .utf8) ?? "{}"
        }

        Task {
            do {
                let arguments = CommandLine.arguments.dropFirst()
                guard arguments.count >= 2 else {
                    throw BumperError.configurationOutputMalformed("Expected root path and command.")
                }

                let root = URL(fileURLWithPath: arguments[arguments.startIndex])
                let command = arguments[arguments.index(after: arguments.startIndex)]
                let commandArguments = arguments.dropFirst(2)
                let resolvedConfiguration = configuration.architectureConfiguration

                switch command {
                case "lint":
                    let report = try await BumperCommands.lint(root: root, configuration: resolvedConfiguration)
                    writePayload(try encodedReport(report))
                case "scan":
                    let output = try await BumperCommands.scan(root: root, configuration: resolvedConfiguration)
                    writePayload(output)
                case "snapshot":
                    let output = try BumperCommands.snapshot(configuration: resolvedConfiguration)
                    writePayload(output)
                case "explain":
                    guard let path = commandArguments.first else {
                        throw BumperError.configurationOutputMalformed("Expected path for explain command.")
                    }
                    let output = try await BumperCommands.explain(
                        path: URL(fileURLWithPath: path),
                        root: root,
                        configuration: resolvedConfiguration
                    )
                    writePayload(output)
                default:
                    throw BumperError.configurationOutputMalformed("Unknown command \\(command).")
                }

                Foundation.exit(0)
            } catch {
                FileHandle.standardError.write(Data((String(describing: error) + "\\n").utf8))
                Foundation.exit(1)
            }
        }

        dispatchMain()
        """
    }

    static func swiftStringLiteral(_ value: String) -> String {
        value.debugDescription
    }

    static func extractPayload(from output: String) throws -> String {
        guard let begin = output.range(of: outputBeginMarker),
              let end = output.range(of: outputEndMarker, range: begin.upperBound..<output.endIndex) else {
            throw BumperError.configurationOutputMalformed(output)
        }

        var payload = String(output[begin.upperBound..<end.lowerBound])
        if StringMatcher.prefix("\n").matches(payload) {
            payload.removeFirst()
        }
        if StringMatcher.suffix("\n").matches(payload) {
            payload.removeLast()
        }
        return payload
    }
}
