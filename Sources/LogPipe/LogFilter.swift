import Foundation

public protocol LogFilter: Sendable {
    func shouldLog(event: LogEvent, config: LoggerConfiguration) -> Bool
}

public struct MinLevelFilter: LogFilter {
    public init() {}

    public func shouldLog(event: LogEvent, config: LoggerConfiguration) -> Bool {
        event.level >= config.minLevel
    }
}

public struct TagFilter: LogFilter {
    public init() {}

    public func shouldLog(event: LogEvent, config: LoggerConfiguration) -> Bool {
        guard let allowed = config.enabledTags, !allowed.isEmpty else {
            return true
        }
        if event.tags.isEmpty {
            return true
        }
        return event.tags.contains { allowed.contains($0) }
    }
}
