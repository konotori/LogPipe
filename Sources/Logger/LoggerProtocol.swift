import Foundation

public protocol LoggerProtocol {
    func log(
        _ level: LogLevel,
        _ message: String,
        tags: [String],
        context: [String: Any],
        file: String,
        function: String,
        line: UInt
    )

    func debug(
        _ message: String,
        tags: [String],
        context: [String: Any],
        file: String,
        function: String,
        line: UInt
    )

    func info(
        _ message: String,
        tags: [String],
        context: [String: Any],
        file: String,
        function: String,
        line: UInt
    )

    func warn(
        _ message: String,
        tags: [String],
        context: [String: Any],
        file: String,
        function: String,
        line: UInt
    )

    func error(
        _ message: String,
        tags: [String],
        context: [String: Any],
        file: String,
        function: String,
        line: UInt
    )

    func fatal(
        _ message: String,
        tags: [String],
        context: [String: Any],
        file: String,
        function: String,
        line: UInt
    )

    func withContext(_ context: [String: Any]) -> LoggerProtocol
    func withTags(_ tags: [String]) -> LoggerProtocol
}

public extension LoggerProtocol {
    func log(
        _ level: LogLevel,
        _ message: String,
        tags: [String] = [],
        context: [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        log(level, message, tags: tags, context: context, file: file, function: function, line: line)
    }

    func debug(
        _ message: String,
        tags: [String] = [],
        context: [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        debug(message, tags: tags, context: context, file: file, function: function, line: line)
    }

    func info(
        _ message: String,
        tags: [String] = [],
        context: [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        info(message, tags: tags, context: context, file: file, function: function, line: line)
    }

    func warn(
        _ message: String,
        tags: [String] = [],
        context: [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        warn(message, tags: tags, context: context, file: file, function: function, line: line)
    }

    func error(
        _ message: String,
        tags: [String] = [],
        context: [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        error(message, tags: tags, context: context, file: file, function: function, line: line)
    }

    func fatal(
        _ message: String,
        tags: [String] = [],
        context: [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        fatal(message, tags: tags, context: context, file: file, function: function, line: line)
    }
}
