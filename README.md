# Logger

A lightweight, production-ready logging kit for iOS built with a single, consistent API. It is designed to be used everywhere (UI, Network, Business) without creating separate logger types. Logs are structured, context-aware, and safe for production.

## Why This Logger

- Single API for all layers: UI, Network, Business, System.
- Structured logs with context and tags.
- Pluggable outputs (console, file, remote).
- Built-in redaction for sensitive data.
- Sampling to reduce noise in production.
- Async processing to keep the main thread clean.

## Key Concepts

- LogEvent: the unit of logging (level, message, tags, context, time, source).
- Logger: public API used by the app.
- Pipeline: Filter -> Sampling -> Redact -> Format -> Emit.
- Destination: a pair of Formatter + Sink.

## Requirements

- iOS 13+
- Swift 5.7+ (SwiftPM)

## Installation (Swift Package Manager)

Add the package to your project:

```swift
.package(url: "https://github.com/your-org/Logger", from: "1.0.0")
```

Then add `Logger` to your target dependencies.

## Quick Start

```swift
import Logger

let logger = Logger(
    config: LoggerConfiguration(minLevel: .debug),
    destinations: [
        LogDestination(formatter: PrettyLogFormatter(), sink: ConsoleLogSink())
    ]
)

logger.info("App started")
logger.debug("Cache hit", tags: ["SYSTEM"])
logger.error("Payment failed", tags: ["BUSINESS"], context: ["orderId": "A123"])
```

## How It Works

Each log call creates a `LogEvent`, then goes through this pipeline:

1. Filter: drop events below `minLevel` or not matching `enabledTags`.
2. Sampling: drop a portion of `debug`/`info` logs in production.
3. Redact: mask sensitive keys (case-insensitive).
4. Format: convert to JSON or readable text.
5. Emit: output to console, file, or remote.

## Core Types

### LogLevel

```swift
public enum LogLevel: Int {
    case debug, info, warn, error, fatal
}
```

### Logger

```swift
public func log(
    _ level: LogLevel,
    _ message: String,
    tags: [String] = [],
    context: [String: Any] = [:]
)
```

### LoggerConfiguration

```swift
public struct LoggerConfiguration {
    var minLevel: LogLevel
    var enabledTags: Set<String>?
    var redactKeys: Set<String>
    var samplingRate: Double
    var includeSourceInfo: Bool
    var includeThread: Bool
}
```

## Usage Examples

### 1) UI Logging

```swift
logger.info("Screen appeared", tags: ["UI"], context: ["screen": "Home"])
logger.info("Button tapped", tags: ["UI"], context: ["button": "BuyNow"])
```

### 2) Network Logging

```swift
logger.debug(
    "Request",
    tags: ["NETWORK"],
    context: ["url": "https://api/login", "method": "POST"]
)

logger.info(
    "Response",
    tags: ["NETWORK"],
    context: ["status": 200, "durationMs": 240]
)
```

### 3) Business Logic Logging

```swift
logger.info("Order created", tags: ["BUSINESS"], context: ["orderId": "A123"])
logger.error("Payment failed", tags: ["BUSINESS"], context: ["reason": "card_declined"])
```

### 4) Context Inheritance

```swift
let userLogger = logger.withContext(["userId": "u1", "sessionId": "s1"])
userLogger.info("Profile opened", tags: ["UI"])
```

### 5) Tag Inheritance

```swift
let networkLogger = logger.withTags(["NETWORK"])
networkLogger.info("Request started", context: ["url": "https://api"])
```

### 6) Redaction

```swift
let logger = Logger(
    config: LoggerConfiguration(redactKeys: ["token", "password", "email"])
)

logger.info(
    "Login",
    context: ["email": "a@b.com", "password": "123", "token": "abc"]
)
// Output will replace those fields with [REDACTED]
```

### 7) Sampling

```swift
var config = LoggerConfiguration(minLevel: .debug)
config.samplingRate = 0.1

let logger = Logger(config: config)
logger.debug("This will be sampled")
logger.warn("This will always be kept")
```

### 8) File Logging

```swift
let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("app.log")
let fileSink = FileLogSink(fileURL: fileURL)

let logger = Logger(
    destinations: [
        LogDestination(formatter: JSONLogFormatter(), sink: fileSink)
    ]
)

logger.info("Saved to file")
```

### 9) Remote Logging

```swift
let remoteSink = RemoteLogSink { formatted, event in
    // Send formatted or event to your server
}

let logger = Logger(
    destinations: [
        LogDestination(formatter: JSONLogFormatter(), sink: remoteSink)
    ]
)
```

### 10) Multiple Destinations

```swift
let logger = Logger(
    destinations: [
        LogDestination(formatter: PrettyLogFormatter(), sink: ConsoleLogSink()),
        LogDestination(formatter: JSONLogFormatter(), sink: fileSink),
        LogDestination(formatter: JSONLogFormatter(), sink: remoteSink)
    ]
)
```

### 11) Runtime Config Updates

```swift
logger.updateConfiguration { config in
    config.minLevel = .warn
    config.samplingRate = 0.2
}
```

## Formatters

- PrettyLogFormatter: readable text for local debugging.
- JSONLogFormatter: structured output for remote collectors.

## Sinks

- ConsoleLogSink: prints to console.
- FileLogSink: appends to a file asynchronously.
- RemoteLogSink: uses a closure to send logs remotely.

## Notes On Performance

- All logging happens on a background queue.
- Redaction happens before formatting and emit.
- Sampling only affects debug and info levels.

## Testing

Run unit tests:

```sh
swift test
```

## Roadmap Ideas

- Payload truncation (size limits for huge context values).
- Batched remote sender with retry.

## License

MIT (or your preferred license)
