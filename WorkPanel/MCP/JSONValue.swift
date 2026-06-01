// WorkPanel/MCP/JSONValue.swift
import Foundation

/// Minimal dynamic JSON value used for JSON-RPC params and results.
enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON") }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

extension JSONValue {
    nonisolated var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    nonisolated var intValue: Int? {
        guard case .number(let n) = self,
              n == n.rounded(),          // reject fractional numbers
              let i = Int(exactly: n)     // reject overflow (returns nil instead of trapping)
        else { return nil }
        return i
    }
    nonisolated var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    nonisolated var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    nonisolated var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    nonisolated var isNull: Bool { if case .null = self { return true }; return false }

    nonisolated subscript(_ key: String) -> JSONValue? { objectValue?[key] }
    nonisolated func contains(_ key: String) -> Bool { objectValue?[key] != nil }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
                     ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
                     ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral,
                     ExpressibleByNilLiteral {
    nonisolated init(stringLiteral value: String) { self = .string(value) }
    nonisolated init(booleanLiteral value: Bool) { self = .bool(value) }
    nonisolated init(integerLiteral value: Int) { self = .number(Double(value)) }
    nonisolated init(floatLiteral value: Double) { self = .number(value) }
    nonisolated init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    nonisolated init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
    nonisolated init(nilLiteral: ()) { self = .null }
}
