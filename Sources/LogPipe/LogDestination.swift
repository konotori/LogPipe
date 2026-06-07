import Foundation

public struct LogDestination: Sendable {
    public let formatter: LogFormatter
    public let sink: LogSink
    /// Events below this level are skipped for this destination only.
    /// The logger-wide `LoggerConfiguration.minLevel` still applies first as a global floor.
    public let minLevel: LogLevel

    public init(formatter: LogFormatter, sink: LogSink, minLevel: LogLevel = .debug) {
        self.formatter = formatter
        self.sink = sink
        self.minLevel = minLevel
    }
}
