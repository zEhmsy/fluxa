import Foundation
import Testing
@testable import FluxaCore

@Suite("NotchCollapse")
struct NotchCollapseTests {
    private let notch = NotchGeometry(gapMinX: 665, gapMaxX: 850)
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func next(
        collapsed: Bool,
        item: NotchCollapse.Frame? = nil,
        fullWidth: Double = 204,
        notch: NotchGeometry?? = nil,
        lastChange: Date? = nil
    ) -> Bool {
        NotchCollapse.nextState(
            collapsed: collapsed, item: item, fullWidth: fullWidth,
            notch: notch ?? self.notch, lastChange: lastChange, now: now)
    }

    @Test("Without a notch the strip never collapses, even off the left edge")
    func noNotch() {
        let item = NotchCollapse.Frame(minX: -10, maxX: 190)
        #expect(next(collapsed: false, item: item, notch: .some(nil)) == false)
        #expect(next(collapsed: true, item: item, notch: .some(nil)) == false)
    }

    @Test("No notch overrides the dwell")
    func noNotchIgnoresDwell() {
        let recent = now.addingTimeInterval(-1)
        #expect(next(collapsed: true, item: .init(minX: 0, maxX: 10), notch: .some(nil), lastChange: recent) == false)
    }

    @Test("A strip starting left of the notch's right edge collapses")
    func collapsesWhenObscured() {
        #expect(next(collapsed: false, item: .init(minX: 841, maxX: 1045)) == true)
    }

    @Test("A strip fully right of the notch stays expanded")
    func staysExpanded() {
        #expect(next(collapsed: false, item: .init(minX: 900, maxX: 1104)) == false)
        #expect(next(collapsed: false, item: .init(minX: 854, maxX: 1058)) == false)
    }

    @Test("A strip touching the notch's right edge collapses")
    func collapsesAtEdge() {
        // Observed on 2.10.1: window at 850..1052 with gapMaxX 850, and macOS hid the item.
        #expect(next(collapsed: false, item: .init(minX: 850, maxX: 1052)) == true)
        #expect(next(collapsed: false, item: .init(minX: 853, maxX: 1055)) == true)
    }

    @Test("Collapsed stays collapsed until room for the full width plus margin")
    func expandNeedsMargin() {
        // slack = maxX - 850; needs 204 + 20 = 224
        #expect(next(collapsed: true, item: .init(minX: 1050, maxX: 1073)) == true)
        #expect(next(collapsed: true, item: .init(minX: 1050, maxX: 1074)) == false)
        #expect(next(collapsed: true, item: .init(minX: 1050, maxX: 1200)) == false)
    }

    @Test("Dwell blocks changes at 29s and allows them at 30s")
    func dwell() {
        let item = NotchCollapse.Frame(minX: 841, maxX: 1045)
        #expect(next(collapsed: false, item: item, lastChange: now.addingTimeInterval(-29)) == false)
        #expect(next(collapsed: false, item: item, lastChange: now.addingTimeInterval(-30)) == true)
        #expect(next(collapsed: false, item: item, lastChange: nil) == true)
    }

    @Test("A missing item leaves the state unchanged")
    func nilItem() {
        #expect(next(collapsed: true) == true)
        #expect(next(collapsed: false) == false)
    }

    @Test("Frames hovering around the threshold flip at most once per dwell")
    func noOscillation() {
        var collapsed = false
        var lastChange: Date?
        var flips = 0
        for second in 0..<30 {
            let t = now.addingTimeInterval(Double(second))
            // Item width follows state, right edge fixed at 1070.
            let width = collapsed ? 23.0 : 204.0
            let item = NotchCollapse.Frame(minX: 1070 - width, maxX: 1070)
            let new = NotchCollapse.nextState(
                collapsed: collapsed, item: item, fullWidth: 204,
                notch: notch, lastChange: lastChange, now: t)
            if new != collapsed { flips += 1; lastChange = t }
            collapsed = new
        }
        #expect(flips <= 1)
    }
}
