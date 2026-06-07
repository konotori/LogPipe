import Foundation

public protocol LogRedactor: Sendable {
    func redact(context: [String: LogValue], keys: Set<String>) -> [String: LogValue]
}

public struct DefaultRedactor: LogRedactor {
    public init() {}

    public func redact(context: [String: LogValue], keys: Set<String>) -> [String: LogValue] {
        guard !keys.isEmpty else { return context }
        let lowercased = Set(keys.map { $0.lowercased() })
        var redacted: [String: LogValue] = [:]
        redacted.reserveCapacity(context.count)
        for (key, value) in context {
            if lowercased.contains(key.lowercased()) {
                redacted[key] = .string("[REDACTED]")
            } else {
                redacted[key] = redact(value: value, keys: lowercased)
            }
        }
        return redacted
    }

    private func redact(value: LogValue, keys: Set<String>) -> LogValue {
        switch value {
        case .object(let object):
            var redacted: [String: LogValue] = [:]
            redacted.reserveCapacity(object.count)
            for (key, value) in object {
                if keys.contains(key.lowercased()) {
                    redacted[key] = .string("[REDACTED]")
                } else {
                    redacted[key] = redact(value: value, keys: keys)
                }
            }
            return .object(redacted)
        case .array(let array):
            return .array(array.map { redact(value: $0, keys: keys) })
        default:
            return value
        }
    }
}
