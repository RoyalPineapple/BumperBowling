import Foundation

public enum BumperError: Error, CustomStringConvertible {
    case configurationAlreadyExists(String)
    case noSubsystemForFile(String)
    case unsupportedLanguage(String)
    case unreadableFile(String)

    public var description: String {
        switch self {
        case .configurationAlreadyExists(let path):
            "Configuration already exists at \(path)."
        case .noSubsystemForFile(let path):
            "No subsystem matches \(path)."
        case .unsupportedLanguage(let path):
            "Only Swift source files are supported: \(path)."
        case .unreadableFile(let path):
            "Could not read source file at \(path)."
        }
    }
}
