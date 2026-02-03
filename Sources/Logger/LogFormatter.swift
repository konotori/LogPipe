import Foundation

public protocol LogFormatter: Sendable {
    func format(event: LogEvent, config: LoggerConfiguration) -> String
}

public struct JSONLogFormatter: LogFormatter {
    public init() {}

    public func format(event: LogEvent, config: LoggerConfiguration) -> String {
        let timestamp = config.dateFormatter.string(from: event.timestamp)
        let record = JSONLogRecord(
            id: event.id.uuidString,
            timestamp: timestamp,
            level: event.level.name,
            message: event.message,
            tags: event.tags,
            context: event.context,
            thread: event.thread,
            source: event.source
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(record)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{\"error\":\"log_encoding_failed\",\"message\":\"\(event.message)\"}"
        }
    }

    private struct JSONLogRecord: Encodable {
        let id: String
        let timestamp: String
        let level: String
        let message: String
        let tags: [String]
        let context: [String: LogValue]
        let thread: String?
        let source: SourceInfo?
    }
}

public struct PrettyLogFormatter: LogFormatter {
    public init() {}

    public func format(event: LogEvent, config: LoggerConfiguration) -> String {
        let timestamp = config.dateFormatter.string(from: event.timestamp)
        let tagPart = event.tags.isEmpty ? "" : "[\(event.tags.joined(separator: ","))]"
        let threadPart = event.thread.map { "{\($0)}" } ?? ""
        let sourcePart: String
        if let source = event.source {
            sourcePart = "(\(source.file):\(source.line) \(source.function))"
        } else {
            sourcePart = ""
        }
        let contextPart: String
        if event.context.isEmpty {
            contextPart = ""
        } else {
            if let data = try? JSONSerialization.data(withJSONObject: event.context.mapValues { $0.toAny() }, options: [.sortedKeys]),
               let string = String(data: data, encoding: .utf8) {
                contextPart = " \(string)"
            } else {
                contextPart = " \(event.context)"
            }
        }

        return "\(timestamp) [\(event.level.name)]\(tagPart)\(threadPart) \(event.message)\(contextPart) \(sourcePart)".trimmingCharacters(in: .whitespaces)
    }
}
