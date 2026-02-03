import Foundation

public struct Logger: LoggerProtocol {
    private let core: LoggerCore
    private let baseContext: [String: LogValue]
    private let baseTags: [String]

    public init(
        config: LoggerConfiguration = .default,
        destinations: [LogDestination] = [LogDestination(formatter: PrettyLogFormatter(), sink: ConsoleLogSink())],
        filters: [LogFilter] = [MinLevelFilter(), TagFilter()],
        redactors: [LogRedactor] = [DefaultRedactor()]
    ) {
        self.core = LoggerCore(config: config, destinations: destinations, filters: filters, redactors: redactors)
        self.baseContext = [:]
        self.baseTags = []
    }

    private init(core: LoggerCore, baseContext: [String: LogValue], baseTags: [String]) {
        self.core = core
        self.baseContext = baseContext
        self.baseTags = baseTags
    }

    public func withContext(_ context: [String: Any]) -> LoggerProtocol {
        var merged = baseContext
        for (key, value) in context {
            merged[key] = LogValue.from(value)
        }
        return Logger(core: core, baseContext: merged, baseTags: baseTags)
    }

    public func withTags(_ tags: [String]) -> LoggerProtocol {
        let merged = baseTags + tags
        return Logger(core: core, baseContext: baseContext, baseTags: merged)
    }

    public func log(
        _ level: LogLevel,
        _ message: String,
        tags: [String] = [],
        context: [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        var mergedContext = baseContext
        for (key, value) in context {
            mergedContext[key] = LogValue.from(value)
        }
        let mergedTags = baseTags + tags
        core.enqueue(
            level: level,
            message: message,
            tags: mergedTags,
            context: mergedContext,
            file: file,
            function: function,
            line: line
        )
    }

    public func debug(
        _ message: String,
        tags: [String] = [],
        context: [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        log(.debug, message, tags: tags, context: context, file: file, function: function, line: line)
    }

    public func info(
        _ message: String,
        tags: [String] = [],
        context: [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        log(.info, message, tags: tags, context: context, file: file, function: function, line: line)
    }

    public func warn(
        _ message: String,
        tags: [String] = [],
        context: [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        log(.warn, message, tags: tags, context: context, file: file, function: function, line: line)
    }

    public func error(
        _ message: String,
        tags: [String] = [],
        context: [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        log(.error, message, tags: tags, context: context, file: file, function: function, line: line)
    }

    public func fatal(
        _ message: String,
        tags: [String] = [],
        context: [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        log(.fatal, message, tags: tags, context: context, file: file, function: function, line: line)
    }

    public func updateConfiguration(_ mutate: @Sendable @escaping (inout LoggerConfiguration) -> Void) {
        core.updateConfiguration(mutate)
    }
}

final class LoggerCore: @unchecked Sendable {
    private var config: LoggerConfiguration
    private var destinations: [LogDestination]
    private var filters: [LogFilter]
    private var redactors: [LogRedactor]
    private let queue: DispatchQueue

    init(config: LoggerConfiguration, destinations: [LogDestination], filters: [LogFilter], redactors: [LogRedactor]) {
        self.config = config
        self.destinations = destinations
        self.filters = filters
        self.redactors = redactors
        self.queue = DispatchQueue(label: "logger.core.queue", qos: .utility)
    }

    func enqueue(
        level: LogLevel,
        message: String,
        tags: [String],
        context: [String: LogValue],
        file: String,
        function: String,
        line: UInt
    ) {
        queue.async {
            let timestamp = self.config.dateProvider()
            let thread = self.config.includeThread ? (Thread.isMainThread ? "main" : "background") : nil
            let source: SourceInfo?
            if self.config.includeSourceInfo {
                source = SourceInfo(file: file, function: function, line: line)
            } else {
                source = nil
            }

            var event = LogEvent(
                timestamp: timestamp,
                level: level,
                message: message,
                tags: tags,
                context: context,
                thread: thread,
                source: source
            )

            if !self.passesFilters(event: event) {
                return
            }

            if self.shouldDropBySampling(level: level) {
                return
            }

            event = self.redact(event: event)

            for destination in self.destinations {
                let formatted = destination.formatter.format(event: event, config: self.config)
                destination.sink.emit(formatted, event: event)
            }
        }
    }

    func updateConfiguration(_ mutate: @Sendable @escaping (inout LoggerConfiguration) -> Void) {
        queue.async {
            mutate(&self.config)
        }
    }

    private func passesFilters(event: LogEvent) -> Bool {
        for filter in filters {
            if !filter.shouldLog(event: event, config: config) {
                return false
            }
        }
        return true
    }

    private func shouldDropBySampling(level: LogLevel) -> Bool {
        guard config.samplingRate < 1.0, level < .warn else {
            return false
        }
        return Double.random(in: 0...1) > config.samplingRate
    }

    private func redact(event: LogEvent) -> LogEvent {
        var redactedContext = event.context
        for redactor in redactors {
            redactedContext = redactor.redact(context: redactedContext, keys: config.redactKeys)
        }

        return LogEvent(
            id: event.id,
            timestamp: event.timestamp,
            level: event.level,
            message: event.message,
            tags: event.tags,
            context: redactedContext,
            thread: event.thread,
            source: event.source
        )
    }
}
