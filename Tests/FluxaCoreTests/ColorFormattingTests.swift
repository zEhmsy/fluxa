import Foundation
import Testing
@testable import FluxaCore

@Suite("ColorFormatting")
struct ColorFormattingTests {

    @Test("Pure primary, secondary, black and white colors format accurately")
    func pureColorsFormatting() {
        #expect(ColorFormatting.hex(red: 1.0, green: 0.0, blue: 0.0) == "#FF0000")
        #expect(ColorFormatting.hex(red: 0.0, green: 1.0, blue: 0.0) == "#00FF00")
        #expect(ColorFormatting.hex(red: 0.0, green: 0.0, blue: 1.0) == "#0000FF")
        #expect(ColorFormatting.hex(red: 1.0, green: 1.0, blue: 0.0) == "#FFFF00")
        #expect(ColorFormatting.hex(red: 0.0, green: 1.0, blue: 1.0) == "#00FFFF")
        #expect(ColorFormatting.hex(red: 1.0, green: 0.0, blue: 1.0) == "#FF00FF")
        #expect(ColorFormatting.hex(red: 1.0, green: 1.0, blue: 1.0) == "#FFFFFF")
        #expect(ColorFormatting.hex(red: 0.0, green: 0.0, blue: 0.0) == "#000000")
    }

    @Test("Rounding behavior at half-step boundaries rounds rather than truncating")
    func roundingBoundaries() {
        // 254.5 / 255 -> rounds to 255 (0xFF)
        let roundUp = 254.5 / 255.0
        #expect(ColorFormatting.hex(red: roundUp, green: roundUp, blue: roundUp) == "#FFFFFF")

        // 127.4 / 255 -> rounds to 127 (0x7F)
        let roundDown = 127.4 / 255.0
        #expect(ColorFormatting.hex(red: roundDown, green: 0.0, blue: 0.0) == "#7F0000")

        // 127.6 / 255 -> rounds to 128 (0x80)
        let roundMidUp = 127.6 / 255.0
        #expect(ColorFormatting.hex(red: roundMidUp, green: 0.0, blue: 0.0) == "#800000")
    }

    @Test("Out-of-range, negative, and NaN inputs clamp safely without crashing")
    func outOfRangeAndNaNHandling() {
        #expect(ColorFormatting.hex(red: -0.5, green: -100.0, blue: -0.001) == "#000000")
        #expect(ColorFormatting.hex(red: 1.5, green: 100.0, blue: 2.0) == "#FFFFFF")
        #expect(ColorFormatting.hex(red: .nan, green: .infinity, blue: -.infinity) == "#00FF00")
    }

    @Test("Output format invariants: always 7 chars, prefix #, uppercase hex digits")
    func formatInvariants() {
        let testValues: [Double] = [0.0, 0.1, 0.25, 0.333, 0.5, 0.667, 0.75, 0.9, 1.0]
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEF")

        for r in testValues {
            for g in testValues {
                for b in testValues {
                    let hex = ColorFormatting.hex(red: r, green: g, blue: b)
                    #expect(hex.count == 7)
                    #expect(hex.hasPrefix("#"))
                    let digits = String(hex.dropFirst())
                    #expect(digits.unicodeScalars.allSatisfy { hexCharacterSet.contains($0) })
                }
            }
        }
    }

    @Test("Benchmark color hex formatting latency across 10,000 iterations")
    func benchmarkColorFormatting() {
        let iterations = 10_000
        let start = DispatchTime.now().uptimeNanoseconds

        for i in 0..<iterations {
            let norm = Double(i % 256) / 255.0
            _ = ColorFormatting.hex(red: norm, green: 1.0 - norm, blue: norm * 0.5)
        }

        let end = DispatchTime.now().uptimeNanoseconds
        let totalNs = end - start
        let perOpUs = Double(totalNs) / Double(iterations) / 1_000.0

        // Pure string formatting is sub-microsecond
        #expect(perOpUs < 50.0)
    }
}
