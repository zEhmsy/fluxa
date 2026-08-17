import SwiftUI

// MARK: - ContributionGridView

/// GitHub's contribution calendar, for tokens: one cell per day, weekdays down, weeks across,
/// oldest week on the left. Cell shade encodes how much was spent that day.
///
/// The intensity scale is relative to the user's own history, as GitHub's is: a heavy week for
/// someone who spends 2M tokens a day should look as heavy as one for someone spending 60M.
/// Thresholds are quartiles of the non-empty days, so the grid re-scales itself instead of needing
/// absolute cutoffs that would be wrong for everybody but one person.
struct ContributionGridView: View {

    /// Tokens per local day.
    let byDay: [Date: Int]
    /// Weeks shown, oldest first.
    var weeks: Int = 26
    /// Base hue; shades are opacity steps of it.
    var tint: Color = .blue

    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: gap) {
                weekdayLabels
                grid
            }
            legend
        }
    }

    // MARK: - Grid

    private var grid: some View {
        HStack(spacing: gap) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                VStack(spacing: gap) {
                    ForEach(week, id: \.self) { day in
                        cellView(for: day)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cellView(for day: Date?) -> some View {
        if let day {
            let tokens = byDay[day] ?? 0
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color(for: tokens))
                .frame(width: cell, height: cell)
                .help(tooltip(day: day, tokens: tokens))
        } else {
            // Padding cell for the partial first/last week — kept as a hole, not a zero, so an
            // empty-looking Monday isn't read as "no work that day".
            Color.clear.frame(width: cell, height: cell)
        }
    }

    private var weekdayLabels: some View {
        VStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { index in
                Text(index % 2 == 1 ? Self.weekdaySymbols[index] : " ")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: cell, alignment: .trailing)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Spacer()
            Text("Less")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(shade(level))
                    .frame(width: 8, height: 8)
            }
            Text("More")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Layout

    /// Weeks as columns of seven optional days, Monday first, ending on the current week.
    private var columns: [[Date?]] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday, matching the weekday labels below

        let today = calendar.startOfDay(for: Date())
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today),
              let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek.start)
        else { return [] }

        return (0..<weeks).map { weekIndex in
            (0..<7).map { dayIndex -> Date? in
                guard let day = calendar.date(
                    byAdding: .day,
                    value: weekIndex * 7 + dayIndex,
                    to: start
                ) else { return nil }
                // Future days in the current week are holes, not empty days.
                return day > today ? nil : day
            }
        }
    }

    // MARK: - Scale

    /// Quartile thresholds of the non-empty days.
    private var thresholds: [Int] {
        let values = byDay.values.filter { $0 > 0 }.sorted()
        guard !values.isEmpty else { return [] }
        return [0.25, 0.5, 0.75].map { quantile in
            values[min(values.count - 1, Int(Double(values.count) * quantile))]
        }
    }

    private func color(for tokens: Int) -> Color {
        guard tokens > 0 else { return shade(0) }
        let steps = thresholds
        guard steps.count == 3 else { return shade(4) }
        if tokens <= steps[0] { return shade(1) }
        if tokens <= steps[1] { return shade(2) }
        if tokens <= steps[2] { return shade(3) }
        return shade(4)
    }

    private func shade(_ level: Int) -> Color {
        switch level {
        case 0:  return Color.primary.opacity(0.06)
        case 1:  return tint.opacity(0.28)
        case 2:  return tint.opacity(0.50)
        case 3:  return tint.opacity(0.75)
        default: return tint
        }
    }

    // MARK: - Text

    private func tooltip(day: Date, tokens: Int) -> String {
        let date = day.formatted(date: .abbreviated, time: .omitted)
        guard tokens > 0 else { return "\(date) — no usage" }
        return "\(date) — \(Self.compact(tokens)) tokens"
    }

    /// "60.2M", "4.8M", "637K" — the grid has no room for grouped digits.
    static func compact(_ tokens: Int) -> String {
        switch tokens {
        case 1_000_000...:
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        case 1_000...:
            return String(format: "%.0fK", Double(tokens) / 1_000)
        default:
            return "\(tokens)"
        }
    }

    private static let weekdaySymbols = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
}
