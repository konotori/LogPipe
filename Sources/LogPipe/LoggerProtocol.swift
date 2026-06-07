import Foundation

public protocol LoggerProtocol: Sendable {
    func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        tags: [String],
        context: @autoclosure () -> [String: Any],
        file: String,
        function: String,
        line: UInt
    )

    func debug(
        _ message: @autoclosure () -> String,
        tags: [String],
        context: @autoclosure () -> [String: Any],
        file: String,
        function: String,
        line: UInt
    )

    func info(
        _ message: @autoclosure () -> String,
        tags: [String],
        context: @autoclosure () -> [String: Any],
        file: String,
        function: String,
        line: UInt
    )

    func warn(
        _ message: @autoclosure () -> String,
        tags: [String],
        context: @autoclosure () -> [String: Any],
        file: String,
        function: String,
        line: UInt
    )

    func error(
        _ message: @autoclosure () -> String,
        tags: [String],
        context: @autoclosure () -> [String: Any],
        file: String,
        function: String,
        line: UInt
    )

    func fatal(
        _ message: @autoclosure () -> String,
        tags: [String],
        context: @autoclosure () -> [String: Any],
        file: String,
        function: String,
        line: UInt
    )

    func withContext(_ context: [String: Any]) -> Self
    func withTags(_ tags: [String]) -> Self

    /// Synchronously drains all pending log events and flushes every sink.
    func flush()
}

public extension LoggerProtocol {
    func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        tags: [String] = [],
        context: @autoclosure () -> [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        log(level, message(), tags: tags, context: context(), file: file, function: function, line: line)
    }

    func debug(
        _ message: @autoclosure () -> String,
        tags: [String] = [],
        context: @autoclosure () -> [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        debug(message(), tags: tags, context: context(), file: file, function: function, line: line)
    }

    func info(
        _ message: @autoclosure () -> String,
        tags: [String] = [],
        context: @autoclosure () -> [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        info(message(), tags: tags, context: context(), file: file, function: function, line: line)
    }

    func warn(
        _ message: @autoclosure () -> String,
        tags: [String] = [],
        context: @autoclosure () -> [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        warn(message(), tags: tags, context: context(), file: file, function: function, line: line)
    }

    func error(
        _ message: @autoclosure () -> String,
        tags: [String] = [],
        context: @autoclosure () -> [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        error(message(), tags: tags, context: context(), file: file, function: function, line: line)
    }

    func fatal(
        _ message: @autoclosure () -> String,
        tags: [String] = [],
        context: @autoclosure () -> [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        fatal(message(), tags: tags, context: context(), file: file, function: function, line: line)
    }

    /// Logs an error-level event with a structured breakdown of the given `Error`
    /// (`error.type`, `error.domain`, `error.code`, `error.description`).
    /// User-provided context keys win over the generated `error.*` keys.
    func error(
        _ message: @autoclosure () -> String,
        error: Error,
        tags: [String] = [],
        context: @autoclosure () -> [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        let nsError = error as NSError
        var merged: [String: Any] = [
            "error.type": String(describing: type(of: error)),
            "error.domain": nsError.domain,
            "error.code": nsError.code,
            "error.description": error.localizedDescription,
        ]
        for (key, value) in context() {
            merged[key] = value
        }
        self.error(message(), tags: tags, context: merged, file: file, function: function, line: line)
    }
}
