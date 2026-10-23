import Charts
import SwiftUI

/// Charges from accounts the user switched off are hidden everywhere.
func visibleCharges(_ charges: [Charge], accounts: [BankAccount]) -> [Charge] {
    let hidden = Set(accounts.filter { !$0.included }.map(\.accountID))
    guard !hidden.isEmpty else { return charges }
    return charges.filter { charge in charge.accountID.map { !hidden.contains($0) } ?? true }
}

/// Net spending in cents (refunds subtract, transfers/payments ignored).
func spendingTotal(_ charges: [Charge]) -> Int {
    charges.reduce(0) { $0 + ($1.isSpending ? $1.amountCents : 0) }
}

struct SectionCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct StatTile: View {
    let label: String
    let cents: Int
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(Money.short(cents))
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let hint {
                Text(hint).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CategoryIcon: View {
    let category: SpendCategory
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.color, in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

struct ChargeRow: View {
    let charge: Charge

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: charge.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(charge.merchant)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(charge.category.title)
                    Text("·")
                    Text(charge.cardName).lineLimit(1)
                    if charge.pending { Text("· Pending") }
                    if charge.source == "tap" {
                        Image(systemName: "wave.3.right").accessibilityLabel("Apple Pay tap")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(Money.string(charge.amountCents, currency: charge.currency))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(charge.isSpending ? .primary : .secondary)
        }
        .contentShape(Rectangle())
    }
}

struct CategoryRow: View {
    let category: SpendCategory
    let cents: Int
    let fraction: Double    // of the largest category, for bar length
    let share: Double       // of total spending, for the label

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: category, size: 28)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(category.title).font(.subheadline)
                    Spacer()
                    Text(Money.short(cents)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    Text("\(Int((share * 100).rounded()))%")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule().fill(category.color)
                            .frame(width: max(4, geo.size.width * fraction))
                    }
                }
                .frame(height: 6)
            }
        }
        .contentShape(Rectangle())
    }
}

struct DayTotal: Identifiable {
    let date: Date
    let cents: Int
    let count: Int
    var id: Date { date }
}

/// Last-30-days bars. Drag or tap to inspect a day; the header shows its total.
struct DailyChart: View {
    let charges: [Charge]
    @State private var selection: Date?

    private var days: [DayTotal] {
        let today = Day.start(.now)
        var cents: [Date: Int] = [:]
        var counts: [Date: Int] = [:]
        for charge in charges where charge.isSpending {
            let key = Day.start(charge.date)
            cents[key, default: 0] += charge.amountCents
            counts[key, default: 0] += 1
        }
        return (0..<30).reversed().compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: today).map {
                DayTotal(date: $0, cents: max(0, cents[$0] ?? 0), count: counts[$0] ?? 0)
            }
        }
    }

    private var weeklyTicks: [Date] {
        let today = Day.start(.now)
        return [28, 21, 14, 7].compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }
    }

    var body: some View {
        let data = days
        let selected = selection.flatMap { s in data.first { Calendar.current.isDate($0.date, inSameDayAs: s) } }
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let selected {
                    Text("\(Day.label(selected.date)) · \(Money.string(selected.cents)) · \(selected.count) \(selected.count == 1 ? "purchase" : "purchases")")
                } else {
                    Text("Last 30 days · \(Money.short(data.reduce(0) { $0 + $1.cents })) · tap a bar")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()

            Chart(data) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Spent", Double(day.cents) / 100)
                )
                .foregroundStyle(Palette.series.opacity(selected == nil || selected?.date == day.date ? 1 : 0.35))
                .cornerRadius(3)
            }
            .chartXSelection(value: $selection)
            .chartXAxis {
                // Weekly ticks that stop short of the right edge, so no label is clipped.
                AxisMarks(values: weeklyTicks) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let dollars = value.as(Double.self) {
                            Text(Money.axis(Int((dollars * 100).rounded())))
                        }
                    }
                }
            }
            .frame(height: 170)
            .accessibilityLabel("Daily spending for the last 30 days")
        }
    }
}
