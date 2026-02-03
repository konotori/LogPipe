import Foundation

public protocol LogSink: Sendable {
    func emit(_ formatted: String, event: LogEvent)
}

public struct ConsoleLogSink: LogSink {
    public init() {}

    public func emit(_ formatted: String, event: LogEvent) {
        print(formatted)
    }
}

public final class FileLogSink: LogSink {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "logger.file.sink")

    public init(fileURL: URL) {
        self.fileURL = fileURL
        ensureFileExists()
    }

    public func emit(_ formatted: String, event: LogEvent) {
        queue.async {
            let line = formatted + "\n"
            guard let data = line.data(using: .utf8) else { return }
            do {
                let handle = try FileHandle(forWritingTo: self.fileURL)
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } catch {
                // Drop silently to avoid impacting app stability.
            }
        }
    }

    private func ensureFileExists() {
        let manager = FileManager.default
        if !manager.fileExists(atPath: fileURL.path) {
            manager.createFile(atPath: fileURL.path, contents: nil)
        }
    }
}

public struct RemoteLogSink: LogSink {
    private let sender: @Sendable (String, LogEvent) -> Void

    public init(sender: @Sendable @escaping (String, LogEvent) -> Void) {
        self.sender = sender
    }

    public func emit(_ formatted: String, event: LogEvent) {
        sender(formatted, event)
    }
}
