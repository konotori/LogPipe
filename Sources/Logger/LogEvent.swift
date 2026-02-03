import Foundation

public struct SourceInfo: Sendable, Encodable, Hashable {
    public let file: String
    public let function: String
    public let line: UInt

    public init(file: String, function: String, line: UInt) {
        self.file = file
        self.function = function
        self.line = line
    }
}

public struct LogEvent: Sendable, Encodable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    public let tags: [String]
    public let context: [String: LogValue]
    public let thread: String?
    public let source: SourceInfo?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        level: LogLevel,
        message: String,
        tags: [String],
        context: [String: LogValue],
        thread: String?,
        source: SourceInfo?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.tags = tags
        self.context = context
        self.thread = thread
        self.source = source
    }
}
