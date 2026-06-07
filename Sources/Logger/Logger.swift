import Foundation

public struct Logger: LoggerProtocol, Sendable {
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

    public func withContext(_ context: [String: Any]) -> Logger {
        var merged = baseContext
        for (key, value) in context {
            merged[key] = LogValue.from(value)
        }
        return Logger(core: core, baseContext: merged, baseTags: baseTags)
    }

    public func withTags(_ tags: [String]) -> Logger {
        let merged = baseTags + tags
        return Logger(core: core, baseContext: baseContext, baseTags: merged)
    }

    public func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        tags: [String] = [],
        context: @autoclosure () -> [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        // Fast path: skip message/context evaluation entirely for disabled levels.
        guard level >= core.currentMinLevel() else { return }

        var mergedContext = baseContext
        for (key, value) in context() {
            mergedContext[key] = LogValue.from(value)
        }
        let mergedTags = baseTags + tags
        core.enqueue(
            level: level,
            message: message(),
            tags: mergedTags,
            context: mergedContext,
            file: file,
            function: function,
            line: line
        )
    }

    public func debug(
        _ message: @autoclosure () -> String,
        tags: [String] = [],
        context: @autoclosure () -> [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        log(.debug, message(), tags: tags, context: context(), file: file, function: function, line: line)
    }

    public func info(
        _ message: @autoclosure () -> String,
        tags: [String] = [],
        context: @autoclosure () -> [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        log(.info, message(), tags: tags, context: context(), file: file, function: function, line: line)
    }

    public func warn(
        _ message: @autoclosure () -> String,
        tags: [String] = [],
        context: @autoclosure () -> [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        log(.warn, message(), tags: tags, context: context(), file: file, function: function, line: line)
    }

    public func error(
        _ message: @autoclosure () -> String,
        tags: [String] = [],
        context: @autoclosure () -> [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        log(.error, message(), tags: tags, context: context(), file: file, function: function, line: line)
    }

    public func fatal(
        _ message: @autoclosure () -> String,
        tags: [String] = [],
        context: @autoclosure () -> [String: Any] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        log(.fatal, message(), tags: tags, context: context(), file: file, function: function, line: line)
    }

    public func updateConfiguration(_ mutate: (inout LoggerConfiguration) -> Void) {
        core.updateConfiguration(mutate)
    }

    public func flush() {
        core.flush()
    }
}

final class LoggerCore: @unchecked Sendable {
    // `state` is only ever accessed while holding `lock`.
    private struct State {
        var config: LoggerConfiguration
        var pendingCount: Int = 0
        var droppedCount: Int = 0
    }

    private let lock = NSLock()
    private var state: State
    private let destinations: [LogDestination]
    private let filters: [LogFilter]
    private let redactors: [LogRedactor]
    private let queue: DispatchQueue

    init(config: LoggerConfiguration, destinations: [LogDestination], filters: [LogFilter], redactors: [LogRedactor]) {
        self.state = State(config: config)
        self.destinations = destinations
        self.filters = filters
        self.redactors = redactors
        self.queue = DispatchQueue(label: "logger.core.queue", qos: .utility)
    }

    func currentMinLevel() -> LogLevel {
        lock.lock()
        defer { lock.unlock() }
        return state.config.minLevel
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
        // Capture call-site state (timestamp, thread) on the caller thread,
        // not on the logger queue.
        let config = currentConfig()
        let timestamp = config.dateProvider()
        let thread = config.includeThread ? (Thread.isMainThread ? "main" : "background") : nil
        let source: SourceInfo?
        if config.includeSourceInfo {
            source = SourceInfo(file: file, function: function, line: line)
        } else {
            source = nil
        }

        let event = LogEvent(
            timestamp: timestamp,
            level: level,
            message: message,
            tags: tags,
            context: context,
            thread: thread,
            source: source
        )

        if level == .fatal {
            // Fatal events are processed synchronously and flushed so they
            // survive an immediate crash.
            queue.sync {
                self.emitDropNoticeIfNeeded(config: config)
                self.process(event: event, config: config)
            }
            flushSinks()
            return
        }

        guard reservePendingSlot(maxQueuedEvents: config.maxQueuedEvents) else {
            return
        }

        queue.async {
            defer { self.releasePendingSlot() }
            self.emitDropNoticeIfNeeded(config: config)
            self.process(event: event, config: config)
        }
    }

    func updateConfiguration(_ mutate: (inout LoggerConfiguration) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        mutate(&state.config)
    }

    func flush() {
        queue.sync {}
        flushSinks()
    }

    private func currentConfig() -> LoggerConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return state.config
    }

    private func reservePendingSlot(maxQueuedEvents: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard state.pendingCount < maxQueuedEvents else {
            state.droppedCount += 1
            return false
        }
        state.pendingCount += 1
        return true
    }

    private func releasePendingSlot() {
        lock.lock()
        defer { lock.unlock() }
        state.pendingCount -= 1
    }

    private func takeDroppedCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let dropped = state.droppedCount
        state.droppedCount = 0
        return dropped
    }

    private func emitDropNoticeIfNeeded(config: LoggerConfiguration) {
        let dropped = takeDroppedCount()
        guard dropped > 0 else { return }
        let notice = LogEvent(
            timestamp: config.dateProvider(),
            level: .warn,
            message: "Logger dropped \(dropped) event(s) due to backpressure",
            tags: [],
            context: [:],
            thread: nil,
            source: nil
        )
        process(event: notice, config: config)
    }

    private func process(event: LogEvent, config: LoggerConfiguration) {
        if !passesFilters(event: event, config: config) {
            return
        }

        if shouldDropBySampling(level: event.level, config: config) {
            return
        }

        let redacted = redact(event: event, config: config)

        for destination in destinations {
            guard redacted.level >= destination.minLevel else { continue }
            let formatted = destination.formatter.format(event: redacted, config: config)
            destination.sink.emit(formatted, event: redacted)
        }
    }

    private func flushSinks() {
        for destination in destinations {
            destination.sink.flush()
        }
    }

    private func passesFilters(event: LogEvent, config: LoggerConfiguration) -> Bool {
        for filter in filters {
            if !filter.shouldLog(event: event, config: config) {
                return false
            }
        }
        return true
    }

    private func shouldDropBySampling(level: LogLevel, config: LoggerConfiguration) -> Bool {
        guard config.samplingRate < 1.0, level < .warn else {
            return false
        }
        return Double.random(in: 0...1) > config.samplingRate
    }

    private func redact(event: LogEvent, config: LoggerConfiguration) -> LogEvent {
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
