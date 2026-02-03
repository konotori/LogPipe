import Foundation

public struct LogDestination: Sendable {
    public let formatter: LogFormatter
    public let sink: LogSink

    public init(formatter: LogFormatter, sink: LogSink) {
        self.formatter = formatter
        self.sink = sink
    }
}
