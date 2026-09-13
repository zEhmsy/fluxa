import Foundation
import Testing
@testable import FluxaCore

@Suite("ProtobufScan")
struct ProtobufScanTests {
    @Test("Single and multi-byte varints decode with the next offset")
    func varints() throws {
        let single = try #require(ProtobufScan.decodeVarint(in: Data([0x2a]), at: 0))
        #expect(single.value == 42)
        #expect(single.nextOffset == 1)

        let multi = try #require(ProtobufScan.decodeVarint(in: Data([0xac, 0x02, 0xff]), at: 0))
        #expect(multi.value == 300)
        #expect(multi.nextOffset == 2)
    }

    @Test("Nested submessages resolve numeric field paths")
    func nestedValue() {
        let message = lengthDelimited(
            field: 1,
            payload: lengthDelimited(field: 4, payload: varint(field: 2, value: 300))
        )
        #expect(ProtobufScan.value(at: [1, 4, 2], in: message) == 300)
        #expect(ProtobufScan.value(at: [1, 4, 3], in: message) == nil)
    }

    @Test("64-bit and 32-bit fields are skipped without losing later fields")
    func fixedWidthFields() throws {
        let message = Data([0x09]) + Data(repeating: 0xaa, count: 8)
            + Data([0x15]) + Data(repeating: 0xbb, count: 4)
            + varint(field: 3, value: 77)
        let fields = try #require(ProtobufScan.fields(in: message))
        #expect(fields.map(\.wireType) == [1, 5, 0])
        #expect(ProtobufScan.value(at: [3], in: message) == 77)
    }

    @Test("Truncated and malformed messages fail without trapping", arguments: [
        Data([0x08, 0x80]),
        Data([0x09, 0x00]),
        Data([0x12, 0x04, 0x01]),
        Data([0x00]),
        Data([0x0b]),
        Data([0x0c]),
        Data([0x0e]),
        Data([0x0f]),
        Data(repeating: 0x80, count: 11),
    ])
    func malformed(message: Data) {
        #expect(ProtobufScan.fields(in: message) == nil)
    }

    @Test("Every truncated prefix of a valid nested message is bounds checked")
    func everyTruncatedPrefix() {
        let message = lengthDelimited(
            field: 1,
            payload: lengthDelimited(field: 4, payload: varint(field: 2, value: 300))
        )
        for length in 0..<message.count {
            _ = ProtobufScan.fields(in: Data(message.prefix(length)))
        }
    }

    @Test("Antigravity token-shaped message exposes all summed leaves")
    func antigravityTokenShape() {
        let usage = varint(field: 1, value: 1_318)
            + varint(field: 2, value: 2_060)
            + varint(field: 3, value: 77)
            + varint(field: 5, value: 8_162)
        let message = lengthDelimited(field: 1, payload: lengthDelimited(field: 4, payload: usage))
        let total = [1, 2, 3, 5].compactMap {
            ProtobufScan.value(at: [1, 4, $0], in: message)
        }.reduce(0, +)
        #expect(total == 11_617)
    }

    private func varint(field: Int, value: UInt64) -> Data {
        encodeVarint(UInt64(field << 3)) + encodeVarint(value)
    }

    private func lengthDelimited(field: Int, payload: Data) -> Data {
        encodeVarint(UInt64((field << 3) | 2)) + encodeVarint(UInt64(payload.count)) + payload
    }

    private func encodeVarint(_ value: UInt64) -> Data {
        var remaining = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(remaining & 0x7f)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while remaining != 0
        return Data(bytes)
    }
}
