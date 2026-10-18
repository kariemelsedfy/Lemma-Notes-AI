import Foundation

/// The small part of CBOR (RFC 8949) that App Attest objects use: unsigned integers, byte and text strings, arrays
/// and maps with text keys, all definite-length. Anything else (tags, floats, indefinite lengths, non-text keys) is
/// refused, which is the safe answer for a parser that reads attacker-supplied bytes.
enum CBORValue: Equatable, Sendable {
    case unsigned(UInt64)
    case bytes(Data)
    case text(String)
    case array([CBORValue])
    case map([String: CBORValue])

    var bytes: Data? {
        if case .bytes(let value) = self { return value }
        return nil
    }

    var map: [String: CBORValue]? {
        if case .map(let value) = self { return value }
        return nil
    }

    var array: [CBORValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var text: String? {
        if case .text(let value) = self { return value }
        return nil
    }
}

enum CBORDecoder {
    static let maximumInputBytes = 64 * 1024
    static let maximumDepth = 8
    static let maximumItems = 64

    /// The one value in `data`, or nil if it is malformed, unsupported, has trailing bytes, or is too large.
    static func decode(_ data: Data) -> CBORValue? {
        guard data.count <= maximumInputBytes else { return nil }
        var reader = Reader(bytes: Array(data))
        guard let value = reader.value(depth: 0), reader.isAtEnd else { return nil }
        return value
    }

    private struct Reader {
        let bytes: [UInt8]
        var index = 0

        var isAtEnd: Bool { index == bytes.count }

        mutating func value(depth: Int) -> CBORValue? {
            guard depth <= CBORDecoder.maximumDepth, let head = next() else { return nil }
            let major = head >> 5
            guard let argument = argument(for: head & 0x1F) else { return nil }
            switch major {
            case 0: return .unsigned(argument)
            case 2: return take(argument).map { .bytes(Data($0)) }
            case 3:
                guard let slice = take(argument), let text = String(bytes: slice, encoding: .utf8) else { return nil }
                return .text(text)
            case 4: return array(count: argument, depth: depth)
            case 5: return map(count: argument, depth: depth)
            default: return nil
            }
        }

        private mutating func array(count: UInt64, depth: Int) -> CBORValue? {
            guard count <= UInt64(CBORDecoder.maximumItems) else { return nil }
            var items: [CBORValue] = []
            for _ in 0..<Int(count) {
                guard let item = value(depth: depth + 1) else { return nil }
                items.append(item)
            }
            return .array(items)
        }

        private mutating func map(count: UInt64, depth: Int) -> CBORValue? {
            guard count <= UInt64(CBORDecoder.maximumItems) else { return nil }
            var entries: [String: CBORValue] = [:]
            for _ in 0..<Int(count) {
                guard case .text(let key)? = value(depth: depth + 1), entries[key] == nil,
                    let item = value(depth: depth + 1)
                else { return nil }
                entries[key] = item
            }
            return .map(entries)
        }

        private mutating func next() -> UInt8? {
            guard index < bytes.count else { return nil }
            defer { index += 1 }
            return bytes[index]
        }

        private mutating func take(_ count: UInt64) -> ArraySlice<UInt8>? {
            guard count <= UInt64(bytes.count - index) else { return nil }
            defer { index += Int(count) }
            return bytes[index..<index + Int(count)]
        }

        /// The head's argument. Indefinite lengths (31) and reserved values are refused.
        private mutating func argument(for info: UInt8) -> UInt64? {
            switch info {
            case 0..<24: return UInt64(info)
            case 24...27:
                let width = 1 << Int(info - 24)
                guard let slice = take(UInt64(width)) else { return nil }
                return slice.reduce(0) { ($0 << 8) | UInt64($1) }
            default: return nil
            }
        }
    }
}
