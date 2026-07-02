import Foundation

public enum BumperError: Error, CustomStringConvertible {
    case configurationAlreadyExists(String)
    case configurationExecutionFailed(String, String)
    case configurationMissing(String)
    case configurationOutputMalformed(String)
    case configurationPackageUnavailable(String)
    case noSubsystemForFile(String)
    case unsupportedLanguage(String)
    case unreadableFile(String)

    public var description: String {
        switch self {
        case .configurationAlreadyExists(let path):
            "Configuration already exists at \(path)."
        case .configurationExecutionFailed(let path, let message):
            "Failed to execute configuration at \(path): \(message)"
        case .configurationMissing(let path):
            "No BumperBowling.swift configuration found at \(path). Run `bumper init` first."
        case .configurationOutputMalformed(let message):
            "Configuration runner produced malformed output: \(message)"
        case .configurationPackageUnavailable(let path):
            "Could not locate the BumperBowling package at \(path). Set BUMPER_PACKAGE_PATH to the package root."
        case .noSubsystemForFile(let path):
            "No subsystem matches \(path)."
        case .unsupportedLanguage(let path):
            "Only Swift source files are supported: \(path)."
        case .unreadableFile(let path):
            "Could not read source file at \(path)."
        }
    }
}
