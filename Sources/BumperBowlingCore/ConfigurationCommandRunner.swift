import Darwin
import CryptoKit
import Foundation

public extension ConfigurationLoader {
    static func loadConfiguration(root: URL) throws -> ArchitectureConfiguration {
        switch try interpretation(root: root) {
        case .configuration(let configuration):
            return configuration
        case .requiresExecution:
            return try executeConfiguration(root: root)
        }
    }

    static func interpretation(root: URL) throws -> ConfigurationInterpretation {
        let configurationURL = root.standardizedFileURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            throw BumperError.configurationMissing(configurationURL.path)
        }
        guard let source = try? String(contentsOf: configurationURL, encoding: .utf8) else {
            throw BumperError.unreadableFile(configurationURL.path)
        }

        return try ConfigurationInterpreter.interpret(source: source)
    }

    static func executeConfiguration(root: URL) throws -> ArchitectureConfiguration {
        let output = try evaluateConfiguration(root: root.standardizedFileURL)
        guard !output.isEmpty else {
            throw BumperError.configurationOutputMalformed("empty configuration payload")
        }
        return try JSONDecoder().decode(ArchitectureConfiguration.self, from: Data(output.utf8))
    }
}

private extension ConfigurationLoader {
    static let outputBeginMarker = "__BUMPER_OUTPUT_BEGIN__"
    static let outputEndMarker = "__BUMPER_OUTPUT_END__"
    static let configurationBuildTimeoutSeconds: TimeInterval = 300
    static let configurationEvaluationTimeoutSeconds: TimeInterval = 60
    static let configurationCommandOutputLimitBytes = 4 * 1024 * 1024
    static let swiftToolchainIdentityTimeoutSeconds: TimeInterval = 10
    static let swiftToolchainIdentityOutputLimitBytes = 16 * 1024

    /// The configuration runner computes a pure value: it evaluates the
    /// repository's `BumperBowling.swift` into an `ArchitectureConfiguration`
    /// and prints it as JSON. It needs no repository access, no writable
    /// paths, and no network, so it runs under a deny-default Darwin sandbox
    /// (the same mechanism SwiftPM uses to evaluate `Package.swift`).
    static let sandboxProfile = """
    (version 1)
    (deny default)
    (import "system.sb")
    (deny network*)
    (allow process-exec)
    (allow file-read*)
    (allow sysctl-read)
    """

    static func evaluateConfiguration(root: URL) throws -> String {
        let root = root.standardizedFileURL
        let configurationURL = root.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            throw BumperError.configurationMissing(configurationURL.path)
        }

        let packageRoot = try bumperPackageRoot()
        let cachedPackage = try makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: packageRoot
        )
        try buildCachedPackageIfNeeded(cachedPackage)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = [
            "-p",
            sandboxProfile,
            cachedPackage.executableURL.path,
        ]
        process.environment = [:]

        let result = try runProcess(
            process,
            timeoutSeconds: configurationEvaluationTimeoutSeconds,
            outputLimitBytes: configurationCommandOutputLimitBytes
        )

        if result.timedOut {
            throw BumperError.configurationExecutionTimedOut(
                configurationURL.path,
                Int(configurationEvaluationTimeoutSeconds)
            )
        }

        if let stream = result.outputTooLargeStream {
            throw BumperError.configurationOutputTooLarge(
                configurationURL.path,
                stream,
                configurationCommandOutputLimitBytes
            )
        }

        let stdoutText = try outputText(result.stdout, stream: "stdout")
        let stderrText = String(data: result.stderr, encoding: .utf8) ?? "<non-UTF-8 stderr>"

        guard result.terminationStatus == 0 else {
            throw BumperError.configurationExecutionFailed(
                configurationURL.path,
                stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return try extractPayload(from: stdoutText)
    }

    static func runProcess(
        _ process: Process,
        timeoutSeconds: TimeInterval,
        outputLimitBytes: Int
    ) throws -> CapturedProcessOutput {
        let stdout = Pipe()
        let stderr = Pipe()
        let stdoutBuffer = BoundedOutputBuffer(limit: outputLimitBytes)
        let stderrBuffer = BoundedOutputBuffer(limit: outputLimitBytes)

        process.standardOutput = stdout
        process.standardError = stderr

        let stdoutHandle = stdout.fileHandleForReading
        let stderrHandle = stderr.fileHandleForReading
        stdoutHandle.readabilityHandler = { handle in
            stdoutBuffer.append(handle.availableData)
        }
        stderrHandle.readabilityHandler = { handle in
            stderrBuffer.append(handle.availableData)
        }
        defer {
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
        }

        try process.run()

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var timedOut = false
        var outputTooLargeStream: String?

        while process.isRunning {
            if stdoutBuffer.hasExceededLimit {
                outputTooLargeStream = "stdout"
                process.terminate()
                break
            }
            if stderrBuffer.hasExceededLimit {
                outputTooLargeStream = "stderr"
                process.terminate()
                break
            }
            if Date() >= deadline {
                timedOut = true
                process.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            let terminationDeadline = Date().addingTimeInterval(5)
            while process.isRunning && Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }

        process.waitUntilExit()
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        stdoutBuffer.append(stdoutHandle.readDataToEndOfFile())
        stderrBuffer.append(stderrHandle.readDataToEndOfFile())

        if outputTooLargeStream == nil {
            if stdoutBuffer.hasExceededLimit {
                outputTooLargeStream = "stdout"
            } else if stderrBuffer.hasExceededLimit {
                outputTooLargeStream = "stderr"
            }
        }

        return CapturedProcessOutput(
            stdout: stdoutBuffer.data,
            stderr: stderrBuffer.data,
            terminationStatus: process.terminationStatus,
            timedOut: timedOut,
            outputTooLargeStream: outputTooLargeStream
        )
    }

    static func outputText(_ data: Data, stream: String) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw BumperError.configurationOutputMalformed("configuration \(stream) was not valid UTF-8")
        }
        return text
    }

    static func makeCachedPackage(
        configurationURL: URL,
        bumperPackageRoot: URL
    ) throws -> CachedPackage {
        let configurationData = try Data(contentsOf: configurationURL)
        let manifest = packageManifest(bumperPackageRoot: bumperPackageRoot)
        let metadata = CachedPackageMetadata(
            configurationContentHash: sha256Hex(configurationData)
        )
        let root = try cachedPackageRoot(
            configurationURL: configurationURL,
            bumperPackageRoot: bumperPackageRoot,
            manifest: manifest
        )
        let sources = root.appendingPathComponent("Sources/BumperConfigurationRunner")

        if cachedPackageIsCurrent(root: root, metadata: metadata) {
            return CachedPackage(
                root: root,
                executableURL: cachedRunnerExecutableURL(in: root),
                needsBuild: false
            )
        }

        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try manifest.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try configurationData.write(to: sources.appendingPathComponent("UserConfiguration.swift"), options: .atomic)
        try runnerSource.write(to: sources.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try JSONEncoder()
            .encode(metadata)
            .write(to: root.appendingPathComponent(CachedPackageMetadata.fileName), options: .atomic)

        return CachedPackage(
            root: root,
            executableURL: cachedRunnerExecutableURL(in: root),
            needsBuild: true
        )
    }

    static func cachedPackageRoot(
        configurationURL: URL,
        bumperPackageRoot: URL,
        manifest: String
    ) throws -> URL {
        let key = [
            "v1",
            configurationURL.standardizedFileURL.path,
            bumperPackageRoot.standardizedFileURL.path,
            try packageRootFingerprint(bumperPackageRoot),
            try swiftToolchainIdentity(),
            sha256Hex(Data(manifest.utf8)),
            sha256Hex(Data(runnerSource.utf8)),
        ].joined(separator: "\n")

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BumperConfigurationLoaderCache")
            .appendingPathComponent(sha256Hex(Data(key.utf8)))
        return root
    }

    static func buildCachedPackageIfNeeded(_ package: CachedPackage) throws {
        guard package.needsBuild || !FileManager.default.isExecutableFile(atPath: package.executableURL.path) else {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swift",
            "build",
            "--package-path",
            package.root.path,
            "--product",
            "BumperConfigurationRunner",
        ]

        let result = try runProcess(
            process,
            timeoutSeconds: configurationBuildTimeoutSeconds,
            outputLimitBytes: configurationCommandOutputLimitBytes
        )

        if result.timedOut {
            throw BumperError.configurationExecutionTimedOut(
                "BumperConfigurationRunner build",
                Int(configurationBuildTimeoutSeconds)
            )
        }

        if let stream = result.outputTooLargeStream {
            throw BumperError.configurationOutputTooLarge(
                "BumperConfigurationRunner build",
                stream,
                configurationCommandOutputLimitBytes
            )
        }

        let stdoutText = try outputText(result.stdout, stream: "build stdout")
        let stderrText = String(data: result.stderr, encoding: .utf8) ?? "<non-UTF-8 stderr>"
        guard result.terminationStatus == 0 else {
            throw BumperError.configurationExecutionFailed(
                "BumperConfigurationRunner build",
                [stdoutText, stderrText]
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        guard FileManager.default.isExecutableFile(atPath: package.executableURL.path) else {
            throw BumperError.configurationOutputMalformed("configuration runner build did not produce an executable")
        }
    }

    static func cachedRunnerExecutableURL(in root: URL) -> URL {
        root.appendingPathComponent(".build/debug/BumperConfigurationRunner")
    }

    static func cachedPackageIsCurrent(root: URL, metadata: CachedPackageMetadata) -> Bool {
        let sources = root.appendingPathComponent("Sources/BumperConfigurationRunner")
        let requiredFiles = [
            root.appendingPathComponent("Package.swift"),
            sources.appendingPathComponent("UserConfiguration.swift"),
            sources.appendingPathComponent("main.swift"),
            root.appendingPathComponent(CachedPackageMetadata.fileName),
        ]

        guard requiredFiles.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: root.appendingPathComponent(CachedPackageMetadata.fileName)),
              let existingMetadata = try? JSONDecoder().decode(CachedPackageMetadata.self, from: data) else {
            return false
        }

        return existingMetadata == metadata
    }

    static func swiftToolchainIdentity() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "--version"]

        let result = try runProcess(
            process,
            timeoutSeconds: swiftToolchainIdentityTimeoutSeconds,
            outputLimitBytes: swiftToolchainIdentityOutputLimitBytes
        )

        if result.timedOut {
            throw BumperError.configurationExecutionTimedOut(
                "swift --version",
                Int(swiftToolchainIdentityTimeoutSeconds)
            )
        }

        if let stream = result.outputTooLargeStream {
            throw BumperError.configurationOutputTooLarge(
                "swift --version",
                stream,
                swiftToolchainIdentityOutputLimitBytes
            )
        }

        let stderrText = String(data: result.stderr, encoding: .utf8) ?? "<non-UTF-8 stderr>"
        guard result.terminationStatus == 0 else {
            throw BumperError.configurationExecutionFailed(
                "swift --version",
                stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return try outputText(result.stdout, stream: "swift --version")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func packageRootFingerprint(_ root: URL) throws -> String {
        let fileManager = FileManager.default
        let roots = [
            root.appendingPathComponent("Package.swift"),
            root.appendingPathComponent("Sources"),
        ]
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        var entries: [String] = []

        for rootURL in roots {
            if let values = try? rootURL.resourceValues(forKeys: keys),
               values.isRegularFile == true {
                entries.append(fingerprintEntry(for: rootURL, packageRoot: root, values: values))
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard StringMatcher.exact("swift").matches(fileURL.pathExtension),
                      let values = try? fileURL.resourceValues(forKeys: keys),
                      values.isRegularFile == true else {
                    continue
                }

                entries.append(fingerprintEntry(for: fileURL, packageRoot: root, values: values))
            }
        }

        return sha256Hex(Data(entries.sorted().joined(separator: "\n").utf8))
    }

    static func fingerprintEntry(
        for fileURL: URL,
        packageRoot: URL,
        values: URLResourceValues
    ) -> String {
        let relativePath = fileURL.path.replacingOccurrences(of: packageRoot.path + "/", with: "")
        let modifiedAt = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(relativePath):\(values.fileSize ?? 0):\(modifiedAt)"
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
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
        import Foundation

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let resolvedConfiguration = configuration.architectureConfiguration
            let payload = String(data: try encoder.encode(resolvedConfiguration), encoding: .utf8) ?? "{}"
            let output = "\(outputBeginMarker)\\n" + payload + "\\n\(outputEndMarker)\\n"
            FileHandle.standardOutput.write(Data(output.utf8))
        } catch {
            FileHandle.standardError.write(Data((String(describing: error) + "\\n").utf8))
            exit(1)
        }
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

private struct CapturedProcessOutput {
    let stdout: Data
    let stderr: Data
    let terminationStatus: Int32
    let timedOut: Bool
    let outputTooLargeStream: String?
}

private struct CachedPackageMetadata: Codable, Equatable {
    static let fileName = ".bumper-cache.json"

    let configurationContentHash: String
}

private struct CachedPackage {
    let root: URL
    let executableURL: URL
    let needsBuild: Bool
}

private final class BoundedOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var storage = Data()
    private var exceededLimit = false

    init(limit: Int) {
        self.limit = Swift.max(1, limit)
    }

    var data: Data {
        lock.withLock {
            storage
        }
    }

    var hasExceededLimit: Bool {
        lock.withLock {
            exceededLimit
        }
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else {
            return
        }

        lock.withLock {
            guard !exceededLimit else {
                return
            }

            let remaining = limit - storage.count
            if chunk.count > remaining {
                if remaining > 0 {
                    storage.append(contentsOf: chunk.prefix(remaining))
                }
                exceededLimit = true
            } else {
                storage.append(chunk)
            }
        }
    }
}
