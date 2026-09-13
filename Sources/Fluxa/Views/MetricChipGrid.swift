import SwiftUI

// MARK: - MetricChipGrid

/// A compact grid layout for metric chips across popover strips (`AgentUsageStripView` and
/// `SystemStatsStripView`).
///
/// Wraps at at most two chips per row:
/// - 1 chip: 1 row, full width
/// - 2 chips: 1 row, two columns
/// - 3 chips: 2 rows (2 chips, then 1 full-width chip)
/// - 4 chips: 2 rows (2 + 2 chips)
///
/// For 1 or 2 chips, it emits a single `HStack(spacing: 10)` matching the original layout bit-for-bit,
/// preventing any popover height change.
struct MetricChipGrid<Item: Identifiable, Chip: View>: View {

    let items: [Item]
    @ViewBuilder let chip: (Item) -> Chip

    var body: some View {
        if items.count <= 2 {
            HStack(spacing: 10) {
                ForEach(items) { item in
                    chip(item)
                }
            }
        } else {
            VStack(spacing: 8) {
                ForEach(rows.indices, id: \.self) { rowIndex in
                    HStack(spacing: 10) {
                        ForEach(rows[rowIndex]) { item in
                            chip(item)
                        }
                    }
                }
            }
        }
    }

    private var rows: [[Item]] {
        stride(from: 0, to: items.count, by: 2).map {
            Array(items[$0..<min($0 + 2, items.count)])
        }
    }
}
