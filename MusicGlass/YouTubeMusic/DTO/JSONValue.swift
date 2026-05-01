import Foundation

enum JSONValue: Codable, Hashable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    subscript(index: Int) -> JSONValue? {
        guard case .array(let array) = self, array.indices.contains(index) else { return nil }
        return array[index]
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var int: Int? {
        if case .number(let value) = self { return Int(value) }
        if case .string(let value) = self { return Int(value) }
        return nil
    }

    var double: Double? {
        if case .number(let value) = self { return value }
        if case .string(let value) = self { return Double(value) }
        return nil
    }

    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var array: [JSONValue] {
        if case .array(let value) = self { return value }
        return []
    }

    var object: [String: JSONValue] {
        if case .object(let value) = self { return value }
        return [:]
    }

    func value(at path: [String]) -> JSONValue? {
        path.reduce(self as JSONValue?) { partial, key in
            guard let partial else { return nil }
            if let index = Int(key) {
                return partial[index]
            }
            return partial[key]
        }
    }

    func string(at path: [String]) -> String? {
        value(at: path)?.string
    }

    func firstString(inPaths paths: [[String]]) -> String? {
        for path in paths {
            if let string = string(at: path), !string.isEmpty {
                return string
            }
        }
        return nil
    }

    func collectObjects(named key: String) -> [JSONValue] {
        var result: [JSONValue] = []
        collectObjects(named: key, into: &result)
        return result
    }

    private func collectObjects(named key: String, into result: inout [JSONValue]) {
        switch self {
        case .object(let object):
            if let value = object[key] {
                result.append(value)
            }
            object.values.forEach { $0.collectObjects(named: key, into: &result) }
        case .array(let array):
            array.forEach { $0.collectObjects(named: key, into: &result) }
        case .string, .number, .bool, .null:
            break
        }
    }

    func collectStrings(named key: String) -> [String] {
        var strings: [String] = []
        collectStrings(named: key, into: &strings)
        return strings
    }

    private func collectStrings(named key: String, into strings: inout [String]) {
        switch self {
        case .object(let object):
            if let value = object[key]?.string {
                strings.append(value)
            }
            object.values.forEach { $0.collectStrings(named: key, into: &strings) }
        case .array(let array):
            array.forEach { $0.collectStrings(named: key, into: &strings) }
        case .string, .number, .bool, .null:
            break
        }
    }
}
