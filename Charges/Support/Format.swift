import Foundation

enum Money {
    /// "$1,234.56"
    static func string(_ cents: Int, currency: String = "USD") -> String {
        (Decimal(cents) / 100).formatted(.currency(code: currency))
    }

    /// Drops the cents for amounts of $1,000 and up: "$1,234" / "$42.10".
    static func short(_ cents: Int, currency: String = "USD") -> String {
        if abs(cents) >= 100_000 {
            return (Decimal(cents / 100)).formatted(.currency(code: currency).precision(.fractionLength(0)))
        }
        return string(cents, currency: currency)
    }

    /// Axis ticks: "$200" rather than "$200.00".
    static func axis(_ cents: Int, currency: String = "USD") -> String {
        guard cents % 100 == 0 else { return string(cents, currency: currency) }
        return (Decimal(cents / 100)).formatted(.currency(code: currency).precision(.fractionLength(0)))
    }

    /// Parses "$12.34", "12.34", "1,234.50 USD" → cents.
    static func parseCents(_ text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
        guard let range = cleaned.range(of: #"\d+(\.\d{1,2})?"#, options: .regularExpression),
              let value = Double(cleaned[range]) else { return nil }
        return Int((value * 100).rounded())
    }
}

enum Day {
    static var calendar: Calendar { Calendar.current }

    static func start(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    static func label(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private static let plainDate: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Plaid gives either a full timestamp or a bare "YYYY-MM-DD"; bare dates
    /// are placed at local noon so they never slip into a neighbouring day.
    static func parsePlaid(datetime: String?, date: String) -> Date {
        if let datetime, let d = isoFull.date(from: datetime) ?? isoBasic.date(from: datetime) {
            return d
        }
        if let d = plainDate.date(from: date) {
            return d.addingTimeInterval(12 * 3600)
        }
        return .now
    }
}
