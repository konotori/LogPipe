import Foundation
import os

public protocol LogSink: Sendable {
    func emit(_ formatted: String, event: LogEvent)

    /// Synchronously flushes any buffered output. Default implementation does nothing.
    func flush()
}

public extension LogSink {
    func flush() {}
}

public struct ConsoleLogSink: LogSink {
    public init() {}

    public func emit(_ formatted: String, event: LogEvent) {
        print(formatted)
    }
}

/// Forwards events to the unified logging system (visible in Console.app and sysdiagnose).
public struct OSLogSink: LogSink {
    private let logger: os.Logger

    public init(subsystem: String = Bundle.main.bundleIdentifier ?? "LogPipe", category: String = "default") {
        self.logger = os.Logger(subsystem: subsystem, category: category)
    }

    public func emit(_ formatted: String, event: LogEvent) {
        // Redaction already happened in the pipeline, so the formatted string is safe to expose.
        logger.log(level: osLogType(for: event.level), "\(formatted, privacy: .public)")
    }

    private func osLogType(for level: LogLevel) -> OSLogType {
        switch level {
        case .debug: return .debug
        case .info: return .info
        case .warn: return .default
        case .error: return .error
        case .fatal: return .fault
        }
    }
}

/// Appends log lines to a file, rotating when the file exceeds `maxFileSize`.
/// Rotated files are named `<name>.1`, `<name>.2`, ... up to `maxArchivedFiles`.
public final class FileLogSink: LogSink, @unchecked Sendable {
    private let fileURL: URL
    private let maxFileSize: UInt64
    private let maxArchivedFiles: Int
    private let queue = DispatchQueue(label: "logpipe.file.sink")

    // Accessed only on `queue`.
    private var handle: FileHandle?
    private var currentSize: UInt64 = 0

    public init(fileURL: URL, maxFileSize: UInt64 = 5 * 1024 * 1024, maxArchivedFiles: Int = 3) {
        self.fileURL = fileURL
        self.maxFileSize = maxFileSize
        self.maxArchivedFiles = maxArchivedFiles
        queue.async {
            self.openHandle()
        }
    }

    deinit {
        try? handle?.close()
    }

    public func emit(_ formatted: String, event: LogEvent) {
        queue.async {
            let line = formatted + "\n"
            guard let data = line.data(using: .utf8) else { return }
            self.write(data)
        }
    }

    public func flush() {
        queue.sync {
            try? handle?.synchronize()
        }
    }

    private func write(_ data: Data) {
        // Recover if the file was deleted out from under us (e.g. tmp cleanup).
        if handle == nil || !FileManager.default.fileExists(atPath: fileURL.path) {
            try? handle?.close()
            handle = nil
            openHandle()
        }
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
            currentSize += UInt64(data.count)
            if currentSize > maxFileSize {
                rotate()
            }
        } catch {
            // Drop silently to avoid impacting app stability; retry opening on next write.
            try? handle.close()
            self.handle = nil
        }
    }

    private func openHandle() {
        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !manager.fileExists(atPath: fileURL.path) {
            manager.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        currentSize = (try? handle.seekToEnd()) ?? 0
        self.handle = handle
    }

    private func rotate() {
        try? handle?.close()
        handle = nil

        let manager = FileManager.default
        let oldest = archiveURL(index: maxArchivedFiles)
        try? manager.removeItem(at: oldest)
        if maxArchivedFiles > 0 {
            for index in stride(from: maxArchivedFiles - 1, through: 1, by: -1) {
                let source = archiveURL(index: index)
                if manager.fileExists(atPath: source.path) {
                    try? manager.moveItem(at: source, to: archiveURL(index: index + 1))
                }
            }
            try? manager.moveItem(at: fileURL, to: archiveURL(index: 1))
        } else {
            try? manager.removeItem(at: fileURL)
        }

        openHandle()
    }

    private func archiveURL(index: Int) -> URL {
        fileURL.appendingPathExtension("\(index)")
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
