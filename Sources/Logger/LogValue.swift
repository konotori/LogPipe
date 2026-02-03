import Foundation

public enum LogValue: Sendable, Encodable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: LogValue])
    case array([LogValue])
    case null

    public static func from(_ value: Any) -> LogValue {
        switch value {
        case let value as LogValue:
            return value
        case let value as String:
            return .string(value)
        case let value as Substring:
            return .string(String(value))
        case let value as Int:
            return .int(value)
        case let value as Int8:
            return .int(Int(value))
        case let value as Int16:
            return .int(Int(value))
        case let value as Int32:
            return .int(Int(value))
        case let value as Int64:
            return .int(Int(value))
        case let value as UInt:
            return .int(Int(value))
        case let value as UInt8:
            return .int(Int(value))
        case let value as UInt16:
            return .int(Int(value))
        case let value as UInt32:
            return .int(Int(value))
        case let value as UInt64:
            return .int(Int(value))
        case let value as Double:
            return .double(value)
        case let value as Float:
            return .double(Double(value))
        case let value as Bool:
            return .bool(value)
        case let value as Date:
            return .string(ISO8601DateFormatter().string(from: value))
        case let value as URL:
            return .string(value.absoluteString)
        case let value as [String: Any]:
            var object: [String: LogValue] = [:]
            object.reserveCapacity(value.count)
            for (key, val) in value {
                object[key] = LogValue.from(val)
            }
            return .object(object)
        case let value as [Any]:
            return .array(value.map { LogValue.from($0) })
        case Optional<Any>.none:
            return .null
        default:
            return .string(String(describing: value))
        }
    }

    public func toAny() -> Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        case .object(let value):
            return value.mapValues { $0.toAny() }
        case .array(let value):
            return value.map { $0.toAny() }
        case .null: return NSNull()
        }
    }
}
