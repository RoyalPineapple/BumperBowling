import Darwin
import CryptoKit
import Foundation

public extension ConfigurationLoader {
    /// Loads `BumperBowling.swift` the way SwiftPM loads `Package.swift`:
    /// compile the project into one cached runner, run its `describe` mode in
    /// a sandbox, read back the configuration it prints. The build is cached
    /// against the project source fingerprint, so the compile happens once
    /// per change, not once per lint.
    static func loadConfiguration(root: URL) throws -> ArchitectureConfiguration {
        let output = try runProjectRunner(
            root: root.standardizedFileURL,
            mode: .describe,
            input: nil
        )
        guard !output.isEmpty else {
            throw BumperError.configurationOutputMalformed("empty configuration payload")
        }
        return try JSONDecoder().decode(ArchitectureConfiguration.self, from: Data(output.utf8))
    }

    /// Runs the same cached runner in `evaluate` mode: the bounded repository
    /// input goes in over stdin, one canonical report plus its telemetry
    /// comes back. Built-in and project rules execute in the same
    /// evaluation invocation.
    static func evaluateRun(root: URL, input: RepositoryInput) throws -> EvaluationRun {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let output = try runProjectRunner(
            root: root.standardizedFileURL,
            mode: .evaluate,
            input: try encoder.encode(input)
        )
        guard !output.isEmpty else {
            throw BumperError.configurationOutputMalformed("empty rule report payload")
        }
        return try JSONDecoder().decode(EvaluationRun.self, from: Data(output.utf8))
    }
}

/// The cached runner's typed modes, selected by its process arguments.
enum ProjectRunnerMode: String, Sendable {
    case describe
    case evaluate
}

extension ConfigurationLoader {
    /// The default evaluation budget in seconds. Legitimately large projects
    /// raise it with `BUMPER_EVALUATION_TIMEOUT_SECONDS`; evaluation is
    /// always bounded.
    static let configurationEvaluationTimeoutSeconds: TimeInterval = 60
    static let evaluationTimeoutEnvironmentKey = "BUMPER_EVALUATION_TIMEOUT_SECONDS"
    /// The runner is a cached artifact built once per configuration change,
    /// so it builds optimized by default: evaluation parses every scanned
    /// source and derives facts, where debug-mode swift-syntax is several
    /// times slower.
    static let defaultProjectRunnerBuildConfiguration = "release"
    static let runnerBuildConfigurationEnvironmentKey = "BUMPER_RUNNER_BUILD_CONFIGURATION"
    static let supportedRunnerBuildConfigurations: Set<String> = ["release", "debug"]

    /// The validated evaluation budget: the documented default when the
    /// override is absent, a positive finite number of seconds when present,
    /// and a loud configuration error otherwise. Invalid input can never
    /// produce an unbounded or zero-length budget.
    static func configurationEvaluationTimeout(
        environment: [String: String]
    ) throws -> TimeInterval {
        guard let raw = environment[evaluationTimeoutEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty else {
            return configurationEvaluationTimeoutSeconds
        }
        guard let seconds = Double(raw), seconds.isFinite, seconds > 0 else {
            throw BumperError.invalidEvaluationTimeout(raw)
        }
        return seconds
    }

    /// The validated runner build configuration: release by default, debug
    /// only through the documented override (for build-constrained hosts like
    /// CI where cold optimized builds are too expensive), and a loud
    /// configuration error for anything else. Cache identity records the
    /// configuration, so the two never share an executable.
    static func projectRunnerBuildConfiguration(
        environment: [String: String]
    ) throws -> String {
        guard let raw = environment[runnerBuildConfigurationEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty else {
            return defaultProjectRunnerBuildConfiguration
        }
        guard supportedRunnerBuildConfigurations.contains(raw) else {
            throw BumperError.invalidRunnerBuildConfiguration(raw)
        }
        return raw
    }

    static func cachedRunnerBuildArguments(packageRoot: URL, buildConfiguration: String) -> [String] {
        [
            "swift",
            "build",
            "--configuration",
            buildConfiguration,
            "--package-path",
            packageRoot.path,
            "--product",
            projectRunnerProductName,
        ]
    }

    static func cachedRunnerExecutableURL(in root: URL, productName: String, buildConfiguration: String) -> URL {
        root.appendingPathComponent(".build/\(buildConfiguration)/\(productName)")
    }

    static func makeCachedPackage(
        configurationURL: URL,
        bumperPackageRoot: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> CachedPackage {
        let buildConfiguration = try projectRunnerBuildConfiguration(environment: environment)
        let configurationData = try Data(contentsOf: configurationURL)
        let repositoryRoot = configurationURL.deletingLastPathComponent()
        let rulePackages = try rulePackageDependencies(root: repositoryRoot)
        let consumerSources = try rulePackages.isEmpty ? consumerConfigurationSources(root: repositoryRoot) : []
        let consumerSourcesHash = consumerConfigurationSourcesHash(consumerSources)
        let rulePackagesHash = try rulePackageDependenciesHash(rulePackages)
        let manifest = packageManifest(
            bumperPackageRoot: bumperPackageRoot,
            rulePackages: rulePackages,
            runnerProductName: projectRunnerProductName
        )
        let metadata = CachedPackageMetadata(
            configurationContentHash: sha256Hex(configurationData),
            consumerSourcesHash: consumerSourcesHash,
            rulePackagesHash: rulePackagesHash,
            runnerProductName: projectRunnerProductName,
            buildConfiguration: buildConfiguration
        )
        let root = try cachedPackageRoot(
            configurationURL: configurationURL,
            bumperPackageRoot: bumperPackageRoot,
            buildConfiguration: buildConfiguration,
            manifest: manifest,
            consumerSourcesHash: consumerSourcesHash,
            rulePackagesHash: rulePackagesHash
        )
        let sources = root.appendingPathComponent("Sources/\(projectRunnerProductName)")

        if cachedPackageIsCurrent(root: root, metadata: metadata) {
            return CachedPackage(
                root: root,
                executableURL: cachedRunnerExecutableURL(
                    in: root,
                    productName: projectRunnerProductName,
                    buildConfiguration: buildConfiguration
                ),
                productName: projectRunnerProductName,
                buildConfiguration: buildConfiguration,
                needsBuild: false
            )
        }

        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try manifest.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try configurationData.write(to: sources.appendingPathComponent("UserConfiguration.swift"), options: .atomic)
        try writeConsumerConfigurationSources(consumerSources, to: sources.appendingPathComponent("ConsumerSources"))
        try runnerSource.write(to: sources.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try JSONEncoder()
            .encode(metadata)
            .write(to: root.appendingPathComponent(CachedPackageMetadata.fileName), options: .atomic)

        return CachedPackage(
            root: root,
            executableURL: cachedRunnerExecutableURL(
                in: root,
                productName: projectRunnerProductName,
                buildConfiguration: buildConfiguration
            ),
            productName: projectRunnerProductName,
            buildConfiguration: buildConfiguration,
            needsBuild: true
        )
    }
}

private extension ConfigurationLoader {
    static let outputBeginMarker = "__BUMPER_OUTPUT_BEGIN__"
    static let outputEndMarker = "__BUMPER_OUTPUT_END__"
    static let configurationBuildTimeoutSeconds: TimeInterval = 600
    static let configurationCommandOutputLimitBytes = 4 * 1024 * 1024
    static let swiftToolchainIdentityTimeoutSeconds: TimeInterval = 10
    static let swiftToolchainIdentityOutputLimitBytes = 16 * 1024
    static let consumerPackageDirectory = ".bumper"
    static let consumerSourceDirectory = ".bumper/Sources"
    static let consumerRulePackageName = ".bumper"
    static let consumerRuleProductName = "BumperRules"
    static let configurationCacheEnvironmentKey = "BUMPER_CACHE_DIR"
    static let projectRunnerProductName = "BumperProjectRunner"

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

    static func runProjectRunner(root: URL, mode: ProjectRunnerMode, input: Data?) throws -> String {
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

        let timeoutSeconds = try configurationEvaluationTimeout(
            environment: ProcessInfo.processInfo.environment
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = [
            "-p",
            sandboxProfile,
            cachedPackage.executableURL.path,
            mode.rawValue,
        ]
        process.environment = [:]

        let result = try runProcess(
            process,
            timeoutSeconds: timeoutSeconds,
            outputLimitBytes: configurationCommandOutputLimitBytes,
            stdin: input
        )

        if result.timedOut {
            throw BumperError.configurationExecutionTimedOut(
                configurationURL.path,
                Int(timeoutSeconds)
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

    static func cachedPackageRoot(
        configurationURL: URL,
        bumperPackageRoot: URL,
        buildConfiguration: String,
        manifest: String,
        consumerSourcesHash: String,
        rulePackagesHash: String
    ) throws -> URL {
        let key = [
            "v4",
            projectRunnerProductName,
            buildConfiguration,
            configurationURL.standardizedFileURL.path,
            bumperPackageRoot.standardizedFileURL.path,
            try packageRootFingerprint(bumperPackageRoot),
            try swiftToolchainIdentity(),
            sha256Hex(Data(manifest.utf8)),
            sha256Hex(Data(runnerSource.utf8)),
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
        process.arguments = cachedRunnerBuildArguments(
            packageRoot: package.root,
            buildConfiguration: package.buildConfiguration
        )

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

    static func cachedPackageIsCurrent(
        root: URL,
        metadata: CachedPackageMetadata
    ) -> Bool {
        let sources = root.appendingPathComponent("Sources/\(projectRunnerProductName)")
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

    /// One runner, two modes. `describe` prints the project's serializable
    /// configuration; `evaluate` reads a bounded `RepositoryInput` from stdin
    /// and prints one `RuleReport`. Both reference the project's `bumper`
    /// entry point.
    static var runnerSource: String {
        """
        import BumperBowlingCore
        import Foundation

        do {
            let mode = CommandLine.arguments.dropFirst().first ?? "describe"
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let payloadData: Data
            switch mode {
            case "describe":
                payloadData = try encoder.encode(bumper.architecture)
            case "evaluate":
                let inputData = FileHandle.standardInput.readDataToEndOfFile()
                let input = try JSONDecoder().decode(RepositoryInput.self, from: inputData)
                payloadData = try encoder.encode(bumper.evaluationRun(input))
            default:
                FileHandle.standardError.write(Data(("unknown runner mode: " + mode + "\\n").utf8))
                exit(64)
            }
            let payload = String(data: payloadData, encoding: .utf8) ?? "{}"
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

struct CachedPackageMetadata: Codable, Equatable {
    static let fileName = ".bumper-cache.json"

    let configurationContentHash: String
    let consumerSourcesHash: String
    let rulePackagesHash: String
    let runnerProductName: String
    let buildConfiguration: String
}

struct CachedPackage {
    let root: URL
    let executableURL: URL
    let productName: String
    let buildConfiguration: String
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
