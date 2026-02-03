import Foundation

public struct LoggerConfiguration {
    public var minLevel: LogLevel
    public var enabledTags: Set<String>?
    public var redactKeys: Set<String>
    public var samplingRate: Double
    public var includeSourceInfo: Bool
    public var includeThread: Bool
    public var dateFormatter: ISO8601DateFormatter
    public var timeZone: TimeZone
    public var dateProvider: () -> Date

    public init(
        minLevel: LogLevel = .info,
        enabledTags: Set<String>? = nil,
        redactKeys: Set<String> = ["password", "token", "authorization", "cookie", "email", "phone"],
        samplingRate: Double = 1.0,
        includeSourceInfo: Bool = true,
        includeThread: Bool = true,
        dateFormatter: ISO8601DateFormatter = ISO8601DateFormatter(),
        timeZone: TimeZone = .current,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.minLevel = minLevel
        self.enabledTags = enabledTags
        self.redactKeys = redactKeys
        self.samplingRate = samplingRate
        self.includeSourceInfo = includeSourceInfo
        self.includeThread = includeThread
        dateFormatter.timeZone = timeZone
        self.dateFormatter = dateFormatter
        self.timeZone = timeZone
        self.dateProvider = dateProvider
    }

    public static var `default`: LoggerConfiguration {
        LoggerConfiguration()
    }
}
