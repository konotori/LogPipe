import Foundation

public enum LogLevel: Int, Comparable, Sendable, CaseIterable, Encodable {
    case debug = 0
    case info = 1
    case warn = 2
    case error = 3
    case fatal = 4

    public var name: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        case .fatal: return "FATAL"
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
