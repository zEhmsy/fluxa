import Foundation

/// Minimal, bounds-checked protobuf field reader for locally generated metadata blobs.
/// Unsupported or malformed input returns `nil`; untrusted bytes must never trap.
package enum ProtobufScan {
    package struct Field: Equatable {
        package let number: Int
        package let wireType: Int
        package let payload: Data
    }

    /// Decodes one unsigned protobuf varint and returns its value and the first unread offset.
    package static func decodeVarint(
        in data: Data,
        at offset: Int
    ) -> (value: UInt64, nextOffset: Int)? {
        guard offset >= 0, offset < data.count else { return nil }

        var value: UInt64 = 0
        var shift = 0
        var cursor = offset

        while cursor < data.count, shift <= 63 {
            let byte = data[cursor]
            let payload = byte & 0x7f
            if shift == 63, payload > 1 { return nil }

            value |= UInt64(payload) << UInt64(shift)
            cursor += 1
            if byte & 0x80 == 0 {
                return (value, cursor)
            }
            shift += 7
        }

        return nil
    }

    /// Iterates a message's top-level fields. Groups and invalid wire types are rejected.
    package static func fields(in data: Data) -> [Field]? {
        var result: [Field] = []
        var cursor = 0

        while cursor < data.count {
            guard let key = decodeVarint(in: data, at: cursor) else { return nil }
            cursor = key.nextOffset

            let fieldNumberValue = key.value >> 3
            guard fieldNumberValue > 0, fieldNumberValue <= UInt64(Int.max) else { return nil }
            let fieldNumber = Int(fieldNumberValue)
            let wireType = Int(key.value & 0x07)

            switch wireType {
            case 0:
                let payloadStart = cursor
                guard let value = decodeVarint(in: data, at: cursor) else { return nil }
                cursor = value.nextOffset
                result.append(Field(
                    number: fieldNumber,
                    wireType: wireType,
                    payload: data.subdata(in: payloadStart..<cursor)
                ))
            case 1:
                guard data.count - cursor >= 8 else { return nil }
                let end = cursor + 8
                result.append(Field(
                    number: fieldNumber,
                    wireType: wireType,
                    payload: data.subdata(in: cursor..<end)
                ))
                cursor = end
            case 2:
                guard let length = decodeVarint(in: data, at: cursor) else { return nil }
                cursor = length.nextOffset
                guard length.value <= UInt64(data.count - cursor) else { return nil }
                let end = cursor + Int(length.value)
                result.append(Field(
                    number: fieldNumber,
                    wireType: wireType,
                    payload: data.subdata(in: cursor..<end)
                ))
                cursor = end
            case 5:
                guard data.count - cursor >= 4 else { return nil }
                let end = cursor + 4
                result.append(Field(
                    number: fieldNumber,
                    wireType: wireType,
                    payload: data.subdata(in: cursor..<end)
                ))
                cursor = end
            default:
                return nil
            }
        }

        return result
    }

    /// Reads a nested varint at a numeric protobuf field path.
    package static func value(at path: [Int], in data: Data) -> UInt64? {
        guard let fieldNumber = path.first, fieldNumber > 0,
              let field = fields(in: data)?.first(where: { $0.number == fieldNumber })
        else { return nil }

        if path.count == 1 {
            guard field.wireType == 0 else { return nil }
            return decodeVarint(in: field.payload, at: 0)?.value
        }

        guard field.wireType == 2 else { return nil }
        return value(at: Array(path.dropFirst()), in: field.payload)
    }
}
