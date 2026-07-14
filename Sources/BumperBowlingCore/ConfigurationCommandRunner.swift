import Darwin
import CryptoKit
import Foundation

public extension ConfigurationLoader {
    /// Loads `BumperBowling.swift` the way SwiftPM loads `Package.swift`:
    /// compile it into a package, run the product in a sandbox, read back the
    /// value it prints. The build is cached against the file's content hash,
    /// so the compile happens once per change, not once per lint.
    static func loadConfiguration(root: URL) throws -> ArchitectureConfiguration {
        let output = try evaluateConfiguration(root: root.standardizedFileURL)
        guard !output.isEmpty else {
            throw BumperError.configurationOutputMalformed("empty configuration payload")
        }
        return try JSONDecoder().decode(ArchitectureConfiguration.self, from: Data(output.utf8))
    }

    static func runCustomRules(
        root: URL,
        configuration: ArchitectureConfiguration,
        repository: RepositoryFacts
    ) throws -> CustomRuleOutput {
        guard configuration.customRules.enabled else {
            return .empty
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let input = CustomRuleInput(configuration: configuration, repository: repository)
        let output = try evaluateCustomRules(
            root: root.standardizedFileURL,
            input: try encoder.encode(input)
        )
        guard !output.isEmpty else {
            throw BumperError.configurationOutputMalformed("empty custom rule payload")
        }
        return try JSONDecoder().decode(CustomRuleOutput.self, from: output)
    }
}

private extension ConfigurationLoader {
    static let outputBeginMarker = "__BUMPER_OUTPUT_BEGIN__"
    static let outputEndMarker = "__BUMPER_OUTPUT_END__"
    static let configurationBuildTimeoutSeconds: TimeInterval = 300
    static let configurationEvaluationTimeoutSeconds: TimeInterval = 60
    static let customRuleEvaluationTimeoutSeconds: TimeInterval = 60
    static let configurationCommandOutputLimitBytes = 4 * 1024 * 1024
    static let swiftToolchainIdentityTimeoutSeconds: TimeInterval = 10
    static let swiftToolchainIdentityOutputLimitBytes = 16 * 1024
    static let consumerPackageDirectory = ".bumper"
    static let consumerSourceDirectory = ".bumper/Sources"
    static let consumerRulePackageName = ".bumper"
    static let consumerRuleProductName = "BumperRules"
    static let configurationCacheEnvironmentKey = "BUMPER_CACHE_DIR"
    static let configurationRunnerProductName = "BumperConfigurationRunner"
    static let customRuleRunnerProductName = "BumperCustomRuleRunner"

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
            bumperPackageRoot: packageRoot,
            runner: .configuration
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

    static func evaluateCustomRules(root: URL, input: Data) throws -> Data {
        let root = root.standardizedFileURL
        let configurationURL = root.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            throw BumperError.configurationMissing(configurationURL.path)
        }

        let packageRoot = try bumperPackageRoot()
        let cachedPackage = try makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: packageRoot,
            runner: .customRules
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
            timeoutSeconds: customRuleEvaluationTimeoutSeconds,
            outputLimitBytes: configurationCommandOutputLimitBytes,
            stdin: input
        )

        if result.timedOut {
            throw BumperError.configurationExecutionTimedOut(
                configurationURL.path,
                Int(customRuleEvaluationTimeoutSeconds)
            )
        }

        if let stream = result.outputTooLargeStream {
            throw BumperError.configurationOutputTooLarge(
                configurationURL.path,
                stream,
                configurationCommandOutputLimitBytes
            )
        }

        let stderrText = String(data: result.stderr, encoding: .utf8) ?? "<non-UTF-8 stderr>"
        guard result.terminationStatus == 0 else {
            throw BumperError.configurationExecutionFailed(
                configurationURL.path,
                stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return result.stdout
    }

    static func runProcess(
        _ process: Process,
        timeoutSeconds: TimeInterval,
        outputLimitBytes: Int,
        stdin: Data? = nil
    ) throws -> CapturedProcessOutput {
        let stdout = Pipe()
        let stderr = Pipe()
        let stdinPipe = stdin.map { _ in Pipe() }
        let stdoutBuffer = BoundedOutputBuffer(limit: outputLimitBytes)
        let stderrBuffer = BoundedOutputBuffer(limit: outputLimitBytes)

        process.standardOutput = stdout
        process.standardError = stderr
        if let stdinPipe {
            process.standardInput = stdinPipe
        }

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
        if let stdin, let stdinPipe {
            stdinPipe.fileHandleForWriting.write(stdin)
            try? stdinPipe.fileHandleForWriting.close()
        }

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
        bumperPackageRoot: URL,
        runner: CachedPackageRunner
    ) throws -> CachedPackage {
        let configurationData = try Data(contentsOf: configurationURL)
        let repositoryRoot = configurationURL.deletingLastPathComponent()
        let rulePackages = try rulePackageDependencies(root: repositoryRoot)
        let consumerSources = try rulePackages.isEmpty ? consumerConfigurationSources(root: repositoryRoot) : []
        let consumerSourcesHash = consumerConfigurationSourcesHash(consumerSources)
        let rulePackagesHash = try rulePackageDependenciesHash(rulePackages)
        let manifest = packageManifest(
            bumperPackageRoot: bumperPackageRoot,
            rulePackages: rulePackages,
            runnerProductName: runner.productName
        )
        let metadata = CachedPackageMetadata(
            configurationContentHash: sha256Hex(configurationData),
            consumerSourcesHash: consumerSourcesHash,
            rulePackagesHash: rulePackagesHash,
            runnerProductName: runner.productName
        )
        let root = try cachedPackageRoot(
            configurationURL: configurationURL,
            bumperPackageRoot: bumperPackageRoot,
            manifest: manifest,
            consumerSourcesHash: consumerSourcesHash,
            rulePackagesHash: rulePackagesHash,
            runner: runner
        )
        let sources = root.appendingPathComponent("Sources/\(runner.productName)")

        if cachedPackageIsCurrent(root: root, metadata: metadata, runner: runner) {
            return CachedPackage(
                root: root,
                executableURL: cachedRunnerExecutableURL(in: root, productName: runner.productName),
                productName: runner.productName,
                needsBuild: false
            )
        }

        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try manifest.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try configurationData.write(to: sources.appendingPathComponent("UserConfiguration.swift"), options: .atomic)
        try writeConsumerConfigurationSources(consumerSources, to: sources.appendingPathComponent("ConsumerSources"))
        try runner.source.write(to: sources.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try JSONEncoder()
            .encode(metadata)
            .write(to: root.appendingPathComponent(CachedPackageMetadata.fileName), options: .atomic)

        return CachedPackage(
            root: root,
            executableURL: cachedRunnerExecutableURL(in: root, productName: runner.productName),
            productName: runner.productName,
            needsBuild: true
        )
    }

    static func cachedPackageRoot(
        configurationURL: URL,
        bumperPackageRoot: URL,
        manifest: String,
        consumerSourcesHash: String,
        rulePackagesHash: String,
        runner: CachedPackageRunner
    ) throws -> URL {
        let key = [
            "v2",
            runner.productName,
            configurationURL.standardizedFileURL.path,
            bumperPackageRoot.standardizedFileURL.path,
            try packageRootFingerprint(bumperPackageRoot),
            try swiftToolchainIdentity(),
            sha256Hex(Data(manifest.utf8)),
            sha256Hex(Data(runner.source.utf8)),
            consumerSourcesHash,
            rulePackagesHash,
        ].joined(separator: "\n")

        let root = configurationCacheRoot()
            .appendingPathComponent(sha256Hex(Data(key.utf8)))
        return root
    }

    static func consumerConfigurationSources(root: URL) throws -> [ConsumerConfigurationSource] {
        let sourceRoot = root.appendingPathComponent(consumerSourceDirectory)
        guard FileManager.default.fileExists(atPath: sourceRoot.path) else {
            return []
        }

        guard let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sources: [ConsumerConfigurationSource] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true,
                  StringMatcher.suffix(".swift").matches(fileURL.lastPathComponent) else {
                continue
            }

            let relativePath = fileURL.path
                .replacingOccurrences(of: sourceRoot.path + "/", with: "")
            guard !relativePath.isEmpty,
                  !relativePath.split(separator: "/").contains(where: isUnsafeRelativePathComponent) else {
                throw BumperError.configurationOutputMalformed(
                    "consumer configuration source has unsafe path: \(relativePath)"
                )
            }

            sources.append(
                ConsumerConfigurationSource(
                    relativePath: relativePath,
                    data: try Data(contentsOf: fileURL)
                )
            )
        }

        return sources.sorted { $0.relativePath < $1.relativePath }
    }

    static func consumerConfigurationSourcesHash(_ sources: [ConsumerConfigurationSource]) -> String {
        let payload = sources.map { source in
            source.relativePath + "\n" + sha256Hex(source.data)
        }.joined(separator: "\n")
        return sha256Hex(Data(payload.utf8))
    }

    static func isUnsafeRelativePathComponent(_ component: Substring) -> Bool {
        let value = String(component)
        return StringMatcher.exact(".").matches(value) || StringMatcher.exact("..").matches(value)
    }

    static func writeConsumerConfigurationSources(
        _ consumerSources: [ConsumerConfigurationSource],
        to destinationRoot: URL
    ) throws {
        guard !consumerSources.isEmpty else {
            return
        }

        for source in consumerSources {
            let destination = destinationRoot.appendingPathComponent(source.relativePath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try source.data.write(to: destination, options: .atomic)
        }
    }

    static func rulePackageDependencies(root: URL) throws -> [RulePackageDependency] {
        let packageRoot = root.appendingPathComponent(consumerPackageDirectory).standardizedFileURL
        guard FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent("Package.swift").path) else {
            return []
        }

        return [
            RulePackageDependency(
                path: packageRoot,
                package: consumerRulePackageName,
                product: consumerRuleProductName
            ),
        ]
    }

    static func rulePackageDependenciesHash(_ packages: [RulePackageDependency]) throws -> String {
        let payload = try packages.map { package in
            [
                package.path.path,
                package.package,
                package.product,
                try packageRootFingerprint(package.path),
            ].joined(separator: "\n")
        }.joined(separator: "\n\n")
        return sha256Hex(Data(payload.utf8))
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
            package.productName,
        ]

        let result = try runProcess(
            process,
            timeoutSeconds: configurationBuildTimeoutSeconds,
            outputLimitBytes: configurationCommandOutputLimitBytes
        )

        if result.timedOut {
            throw BumperError.configurationExecutionTimedOut(
                "\(package.productName) build",
                Int(configurationBuildTimeoutSeconds)
            )
        }

        if let stream = result.outputTooLargeStream {
            throw BumperError.configurationOutputTooLarge(
                "\(package.productName) build",
                stream,
                configurationCommandOutputLimitBytes
            )
        }

        let stdoutText = try outputText(result.stdout, stream: "build stdout")
        let stderrText = String(data: result.stderr, encoding: .utf8) ?? "<non-UTF-8 stderr>"
        guard result.terminationStatus == 0 else {
            throw BumperError.configurationExecutionFailed(
                "\(package.productName) build",
                [stdoutText, stderrText]
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        guard FileManager.default.isExecutableFile(atPath: package.executableURL.path) else {
            throw BumperError.configurationOutputMalformed("\(package.productName) build did not produce an executable")
        }
    }

    static func cachedRunnerExecutableURL(in root: URL, productName: String) -> URL {
        root.appendingPathComponent(".build/debug/\(productName)")
    }

    static func cachedPackageIsCurrent(
        root: URL,
        metadata: CachedPackageMetadata,
        runner: CachedPackageRunner
    ) -> Bool {
        let sources = root.appendingPathComponent("Sources/\(runner.productName)")
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

    static func packageManifest(
        bumperPackageRoot: URL,
        rulePackages: [RulePackageDependency],
        runnerProductName: String
    ) -> String {
        let dependencyEntries = ([
            ".package(name: \"BumperBowling\", path: \(swiftStringLiteral(bumperPackageRoot.path)))",
            ".package(url: \"https://github.com/swiftlang/swift-syntax.git\", from: \"602.0.0\")",
        ] + rulePackages.map { package in
            ".package(path: \(swiftStringLiteral(package.path.path)))"
        }).joined(separator: ",\n                ")
        let targetDependencies = ([
            ".product(name: \"BumperBowlingCore\", package: \"BumperBowling\")",
            ".product(name: \"SwiftParser\", package: \"swift-syntax\")",
            ".product(name: \"SwiftSyntax\", package: \"swift-syntax\")",
        ] + rulePackages.map { package in
            ".product(name: \(swiftStringLiteral(package.product)), package: \(swiftStringLiteral(package.package)))"
        }).joined(separator: ",\n                        ")

        return """
        // swift-tools-version: 6.2
        import PackageDescription

        let package = Package(
            name: "BumperConfigurationLoader",
            platforms: [
                .macOS(.v15),
            ],
            dependencies: [
                \(dependencyEntries),
            ],
            targets: [
                .executableTarget(
                    name: \(swiftStringLiteral(runnerProductName)),
                    dependencies: [
                        \(targetDependencies),
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

    static var customRuleRunnerSource: String {
        """
        import BumperBowlingCore
        import Foundation

        do {
            let inputData = FileHandle.standardInput.readDataToEndOfFile()
            let input = try JSONDecoder().decode(CustomRuleInput.self, from: inputData)
            let output = try await customRules.evaluateConcurrently(
                input,
                maxConcurrentRuleJobs: input.configuration.customRules.maxConcurrentRuleJobs
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(output))
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

extension ConfigurationLoader {
    static func configurationCacheRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let environmentPath = environment[configurationCacheEnvironmentKey],
           !environmentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: environmentPath).standardizedFileURL
        }

        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BumperConfigurationLoaderCache")
            .standardizedFileURL
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
    let consumerSourcesHash: String
    let rulePackagesHash: String
    let runnerProductName: String
}

private struct CachedPackage {
    let root: URL
    let executableURL: URL
    let productName: String
    let needsBuild: Bool
}

private struct ConsumerConfigurationSource {
    let relativePath: String
    let data: Data
}

private struct RulePackageDependency {
    let path: URL
    let package: String
    let product: String
}

private struct CachedPackageRunner {
    let productName: String
    let source: String

    static var configuration: CachedPackageRunner {
        CachedPackageRunner(
            productName: ConfigurationLoader.configurationRunnerProductName,
            source: ConfigurationLoader.runnerSource
        )
    }

    static var customRules: CachedPackageRunner {
        CachedPackageRunner(
            productName: ConfigurationLoader.customRuleRunnerProductName,
            source: ConfigurationLoader.customRuleRunnerSource
        )
    }
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
