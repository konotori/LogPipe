import Foundation

public struct LoggerConfiguration: Sendable {
    public var minLevel: LogLevel
    public var enabledTags: Set<String>?
    public var redactKeys: Set<String>
    public var samplingRate: Double
    public var includeSourceInfo: Bool
    public var includeThread: Bool
    public var maxQueuedEvents: Int
    public var dateFormatStyle: Date.ISO8601FormatStyle
    public var dateProvider: @Sendable () -> Date

    public init(
        minLevel: LogLevel = .info,
        enabledTags: Set<String>? = nil,
        redactKeys: Set<String> = ["password", "token", "authorization", "cookie", "email", "phone"],
        samplingRate: Double = 1.0,
        includeSourceInfo: Bool = true,
        includeThread: Bool = true,
        maxQueuedEvents: Int = 1_000,
        timeZone: TimeZone = .current,
        dateProvider: @Sendable @escaping () -> Date = Date.init
    ) {
        self.minLevel = minLevel
        self.enabledTags = enabledTags
        self.redactKeys = redactKeys
        self.samplingRate = samplingRate
        self.includeSourceInfo = includeSourceInfo
        self.includeThread = includeThread
        self.maxQueuedEvents = maxQueuedEvents
        self.dateFormatStyle = Date.ISO8601FormatStyle(timeZone: timeZone)
        self.dateProvider = dateProvider
    }

    public static var `default`: LoggerConfiguration {
        LoggerConfiguration()
    }
}
