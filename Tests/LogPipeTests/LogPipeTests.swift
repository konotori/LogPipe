import Foundation
import Testing
@testable import LogPipe

final class CapturingSink: LogSink, @unchecked Sendable {
	private let queue = DispatchQueue(label: "logpipe.tests.capturing.sink")
	private var records: [(String, LogEvent)] = []
	
	func emit(_ formatted: String, event: LogEvent) {
		queue.sync {
			records.append((formatted, event))
		}
	}
	
	func allRecords() -> [(String, LogEvent)] {
		queue.sync { records }
	}
	
	func count() -> Int {
		queue.sync { records.count }
	}
}

func waitForCount(_ sink: CapturingSink, _ count: Int, timeoutNs: UInt64 = 1_000_000_000) async -> Bool {
	let start = DispatchTime.now().uptimeNanoseconds
	while DispatchTime.now().uptimeNanoseconds - start < timeoutNs {
		if sink.count() >= count {
			return true
		}
		try? await Task.sleep(nanoseconds: 10_000_000)
	}
	return false
}

struct LoggerTests {
	
	@Test func logLevelComparable_Ordering_Ascending() {
		#expect(LogLevel.debug < .info)
		#expect(LogLevel.info < .warn)
		#expect(LogLevel.warn < .error)
		#expect(LogLevel.error < .fatal)
	}
	
	@Test func minLevelFilter_BlocksLowerLevels_OnlyWarnAndAbove() async {
		var config = LoggerConfiguration(minLevel: .warn)
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		let sink = CapturingSink()
		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: PrettyLogFormatter(), sink: sink)]
		)
		
		logger.debug("debug")
		logger.info("info")
		logger.warn("warn")
		
		let received = await waitForCount(sink, 1)
		#expect(received)
		#expect(sink.count() == 1)
		#expect(sink.allRecords().first?.1.level == .warn)
	}
	
	@Test func tagFilter_AllowsEnabledTagsAndUntagged_BlocksOthers() async {
		var config = LoggerConfiguration(minLevel: .debug)
		config.enabledTags = ["NETWORK"]
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		let sink = CapturingSink()
		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: PrettyLogFormatter(), sink: sink)]
		)
		
		logger.info("ui", tags: ["UI"])
		logger.info("network", tags: ["NETWORK"])
		logger.info("untagged")
		
		let received = await waitForCount(sink, 2)
		#expect(received)
		let levels = sink.allRecords().map { $0.1.message }
		#expect(levels.contains("network"))
		#expect(levels.contains("untagged"))
		#expect(!levels.contains("ui"))
	}
	
	@Test func samplingRateZero_DropsDebugAndInfo_KeepsWarnAndAbove() async {
		var config = LoggerConfiguration(minLevel: .debug)
		config.samplingRate = 0.0
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		let sink = CapturingSink()
		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: PrettyLogFormatter(), sink: sink)]
		)
		
		logger.debug("debug")
		logger.info("info")
		logger.warn("warn")
		
		let received = await waitForCount(sink, 1)
		#expect(received)
		#expect(sink.count() == 1)
		#expect(sink.allRecords().first?.1.level == .warn)
	}
	
	@Test func redactor_MasksSensitiveKeys_CaseInsensitive() async {
		var config = LoggerConfiguration(minLevel: .debug)
		config.redactKeys = ["token", "password", "email"]
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		let sink = CapturingSink()
		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: JSONLogFormatter(), sink: sink)]
		)
		
		logger.info(
			"login",
			context: [
				"token": "abc",
				"Email": "a@b.com",
				"profile": ["password": "123"],
				"ok": true
			]
		)
		
		let received = await waitForCount(sink, 1)
		#expect(received)
		let record = sink.allRecords().first?.1
		let context = record?.context ?? [:]
		#expect(context["token"] == .string("[REDACTED]"))
		#expect(context["Email"] == .string("[REDACTED]"))
		if case .object(let profile)? = context["profile"] {
			#expect(profile["password"] == .string("[REDACTED]"))
		} else {
			#expect(Bool(false))
		}
		#expect(context["ok"] == .bool(true))
	}
	
	@Test func jsonFormatter_OutputsStructuredJson_ContainsKeys() async {
		var config = LoggerConfiguration(minLevel: .debug)
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		let sink = CapturingSink()
		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: JSONLogFormatter(), sink: sink)]
		)
		
		logger.info("hello", tags: ["UI"], context: ["count": 1])
		
		let received = await waitForCount(sink, 1)
		#expect(received)
		let formatted = sink.allRecords().first?.0 ?? ""
		#expect(formatted.contains("\"level\":\"INFO\""))
		#expect(formatted.contains("\"message\":\"hello\""))
		#expect(formatted.contains("\"tags\":[\"UI\"]"))
		#expect(formatted.contains("\"context\""))
	}
	
	@Test func prettyFormatter_IncludesMessageAndTags_ReadableFormat() async {
		var config = LoggerConfiguration(minLevel: .debug)
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		let sink = CapturingSink()
		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: PrettyLogFormatter(), sink: sink)]
		)
		
		logger.info("hello", tags: ["UI"])
		
		let received = await waitForCount(sink, 1)
		#expect(received)
		let formatted = sink.allRecords().first?.0 ?? ""
		#expect(formatted.contains("[INFO]"))
		#expect(formatted.contains("[UI]"))
		#expect(formatted.contains("hello"))
	}
	
	@Test func withContext_MergesAndOverrides_DefaultContext() async {
		var config = LoggerConfiguration(minLevel: .debug)
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		let sink = CapturingSink()
		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: PrettyLogFormatter(), sink: sink)]
		)
		
		let child = logger.withContext(["userId": "u1", "role": "member"])
		child.info("test", context: ["role": "admin"])
		
		let received = await waitForCount(sink, 1)
		#expect(received)
		let ctx = sink.allRecords().first?.1.context ?? [:]
		#expect(ctx["userId"] == .string("u1"))
		#expect(ctx["role"] == .string("admin"))
	}
	
	@Test func withTags_AppendsBaseTags_PreservesNewTags() async {
		var config = LoggerConfiguration(minLevel: .debug)
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		let sink = CapturingSink()
		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: PrettyLogFormatter(), sink: sink)]
		)
		
		let child = logger.withTags(["NETWORK"])
		child.info("test", tags: ["Auth"])
		
		let received = await waitForCount(sink, 1)
		#expect(received)
		let tags = sink.allRecords().first?.1.tags ?? []
		#expect(tags.contains("NETWORK"))
		#expect(tags.contains("Auth"))
	}
	
	@Test func fileLogSink_WritesToFile_ContainsMessage() async throws {
		var config = LoggerConfiguration(minLevel: .debug)
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("logger-test.log")
		try? FileManager.default.removeItem(at: fileURL)
		
		let fileSink = FileLogSink(fileURL: fileURL)
		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: PrettyLogFormatter(), sink: fileSink)]
		)
		
		logger.info("file-write")
		
		let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
		var contents = ""
		while DispatchTime.now().uptimeNanoseconds < deadline {
			if let data = try? Data(contentsOf: fileURL),
			   let text = String(data: data, encoding: .utf8),
			   !text.isEmpty {
				contents = text
				break
			}
			try? await Task.sleep(nanoseconds: 10_000_000)
		}
		
		#expect(contents.contains("file-write"))
	}
	
	@Test func loggerTypes_AreSendable_CompileTimeCheck() {
		func requiresSendable<T: Sendable>(_: T.Type) {}
		requiresSendable(Logger.self)
		requiresSendable(LoggerConfiguration.self)
		requiresSendable((any LoggerProtocol).self)
	}

	@Test @MainActor func threadInfo_CapturedAtCallSite_MainThreadIsMain() async {
		var config = LoggerConfiguration(minLevel: .debug)
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		let sink = CapturingSink()
		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: PrettyLogFormatter(), sink: sink)]
		)

		logger.info("from main")

		let received = await waitForCount(sink, 1)
		#expect(received)
		#expect(sink.allRecords().first?.1.thread == "main")
	}

	@Test func flush_DrainsQueueSynchronously_EventVisibleImmediately() {
		var config = LoggerConfiguration(minLevel: .debug)
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		let sink = CapturingSink()
		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: PrettyLogFormatter(), sink: sink)]
		)

		logger.info("a")
		logger.info("b")
		logger.flush()

		#expect(sink.count() == 2)
	}

	@Test func fatal_EmitsSynchronously_NoWaitNeeded() {
		var config = LoggerConfiguration(minLevel: .debug)
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		let sink = CapturingSink()
		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: PrettyLogFormatter(), sink: sink)]
		)

		logger.fatal("crash")

		#expect(sink.count() == 1)
		#expect(sink.allRecords().first?.1.level == .fatal)
	}

	@Test func autoclosure_NotEvaluated_WhenBelowMinLevel() {
		let config = LoggerConfiguration(minLevel: .warn)
		let sink = CapturingSink()
		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: PrettyLogFormatter(), sink: sink)]
		)

		final class Flag: @unchecked Sendable { var evaluated = false }
		let flag = Flag()
		func expensiveMessage() -> String {
			flag.evaluated = true
			return "expensive"
		}

		logger.debug(expensiveMessage())
		logger.flush()

		#expect(!flag.evaluated)
		#expect(sink.count() == 0)
	}

	@Test func fileLogSink_RotatesFile_WhenExceedingMaxSize() throws {
		var config = LoggerConfiguration(minLevel: .debug)
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		config.includeSourceInfo = false
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("logger-rotation-test", isDirectory: true)
		try? FileManager.default.removeItem(at: directory)
		let fileURL = directory.appendingPathComponent("app.log")

		let fileSink = FileLogSink(fileURL: fileURL, maxFileSize: 64, maxArchivedFiles: 2)
		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: PrettyLogFormatter(), sink: fileSink)]
		)

		for index in 0..<10 {
			logger.info("rotation-line-\(index)")
		}
		logger.flush()

		let archived = fileURL.appendingPathExtension("1")
		#expect(FileManager.default.fileExists(atPath: fileURL.path))
		#expect(FileManager.default.fileExists(atPath: archived.path))
	}

	@Test func fileLogSink_RecoversAfterFileDeleted_KeepsLogging() async throws {
		var config = LoggerConfiguration(minLevel: .debug)
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("logger-recover-test.log")
		try? FileManager.default.removeItem(at: fileURL)

		let fileSink = FileLogSink(fileURL: fileURL)
		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: PrettyLogFormatter(), sink: fileSink)]
		)

		logger.info("before-delete")
		logger.flush()
		try FileManager.default.removeItem(at: fileURL)

		logger.info("after-delete")
		logger.flush()

		let contents = try String(contentsOf: fileURL, encoding: .utf8)
		#expect(contents.contains("after-delete"))
	}

	@Test func backpressure_DropsEventsBeyondLimit_ReportsDropCount() {
		var config = LoggerConfiguration(minLevel: .debug)
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		config.maxQueuedEvents = 1

		let started = DispatchSemaphore(value: 0)
		let release = DispatchSemaphore(value: 0)
		let sink = CapturingSink()
		let blockingSink = RemoteLogSink { formatted, event in
			sink.emit(formatted, event: event)
			if event.message == "blocker" {
				started.signal()
				release.wait()
			}
		}

		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: PrettyLogFormatter(), sink: blockingSink)]
		)

		logger.info("blocker")
		started.wait() // blocker is now occupying the queue
		logger.info("dropped") // pending slot full -> dropped
		release.signal()
		logger.flush()
		logger.info("after")
		logger.flush()

		let messages = sink.allRecords().map { $0.1.message }
		#expect(messages.contains("blocker"))
		#expect(!messages.contains("dropped"))
		#expect(messages.contains("after"))
		#expect(messages.contains { $0.contains("dropped 1 event(s)") })
	}

	@Test func perDestinationMinLevel_RoutesByLevel_EachSinkOwnThreshold() {
		var config = LoggerConfiguration(minLevel: .debug)
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		let consoleSink = CapturingSink()
		let remoteSink = CapturingSink()
		let logger = Logger(
			config: config,
			destinations: [
				LogDestination(formatter: PrettyLogFormatter(), sink: consoleSink, minLevel: .debug),
				LogDestination(formatter: JSONLogFormatter(), sink: remoteSink, minLevel: .error)
			]
		)

		logger.debug("debug")
		logger.info("info")
		logger.error("error")
		logger.flush()

		#expect(consoleSink.count() == 3)
		#expect(remoteSink.count() == 1)
		#expect(remoteSink.allRecords().first?.1.level == .error)
	}

	@Test func errorOverload_ExtractsStructuredErrorFields_UserContextWins() {
		var config = LoggerConfiguration(minLevel: .debug)
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		let sink = CapturingSink()
		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: JSONLogFormatter(), sink: sink)]
		)

		let underlying = NSError(domain: "NSURLErrorDomain", code: -1009, userInfo: [
			NSLocalizedDescriptionKey: "The Internet connection appears to be offline."
		])
		logger.error("Payment failed", error: underlying, context: ["error.code": 42, "orderId": "A123"])
		logger.flush()

		#expect(sink.count() == 1)
		let event = sink.allRecords().first?.1
		#expect(event?.level == .error)
		let ctx = event?.context ?? [:]
		#expect(ctx["error.domain"] == .string("NSURLErrorDomain"))
		#expect(ctx["error.code"] == .int(42)) // user-provided context overrides
		#expect(ctx["error.description"] == .string("The Internet connection appears to be offline."))
		#expect(ctx["orderId"] == .string("A123"))
	}

	@Test func remoteSink_ReceivesFormattedOutput_UsesFormatter() async {
		var config = LoggerConfiguration(minLevel: .debug)
		config.dateProvider = { Date(timeIntervalSince1970: 0) }
		
		let sink = CapturingSink()
		let remoteSink = RemoteLogSink { formatted, event in
			sink.emit(formatted, event: event)
		}
		
		let logger = Logger(
			config: config,
			destinations: [LogDestination(formatter: JSONLogFormatter(), sink: remoteSink)]
		)
		
		logger.error("remote")
		
		let received = await waitForCount(sink, 1)
		#expect(received)
		let formatted = sink.allRecords().first?.0 ?? ""
		#expect(formatted.contains("\"message\":\"remote\""))
	}
}
