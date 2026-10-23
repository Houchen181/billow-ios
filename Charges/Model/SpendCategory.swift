import SwiftUI

enum SpendCategory: String, CaseIterable, Identifiable, Codable {
    case shopping, dining, groceries, transport, bills, health, travel, entertainment, other
    /// Card payments, transfers, income — tracked but never counted as spending.
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shopping: "Shopping"
        case .dining: "Dining"
        case .groceries: "Groceries"
        case .transport: "Transport"
        case .bills: "Bills & services"
        case .health: "Health & care"
        case .travel: "Travel"
        case .entertainment: "Entertainment"
        case .other: "Other"
        case .transfer: "Not spending"
        }
    }

    var symbol: String {
        switch self {
        case .shopping: "bag.fill"
        case .dining: "fork.knife"
        case .groceries: "cart.fill"
        case .transport: "car.fill"
        case .bills: "doc.text.fill"
        case .health: "heart.fill"
        case .travel: "airplane"
        case .entertainment: "ticket.fill"
        case .other: "square.grid.2x2.fill"
        case .transfer: "arrow.left.arrow.right"
        }
    }

    /// Fixed slot per category (palette order 1…8), gray for the rest.
    var color: Color {
        switch self {
        case .shopping: Palette.blue
        case .dining: Palette.orange
        case .groceries: Palette.aqua
        case .transport: Palette.yellow
        case .bills: Palette.magenta
        case .health: Palette.green
        case .travel: Palette.violet
        case .entertainment: Palette.red
        case .other: Palette.gray
        case .transfer: Palette.quiet
        }
    }

    var countsAsSpending: Bool { self != .transfer }

    /// Maps Plaid's personal_finance_category onto our fixed set.
    static func fromPlaid(primary: String?, detailed: String?) -> SpendCategory {
        guard let primary else { return .other }
        switch primary {
        case "FOOD_AND_DRINK":
            return detailed == "FOOD_AND_DRINK_GROCERIES" ? .groceries : .dining
        case "GENERAL_MERCHANDISE", "HOME_IMPROVEMENT": return .shopping
        case "TRANSPORTATION": return .transport
        case "TRAVEL": return .travel
        case "RENT_AND_UTILITIES", "GENERAL_SERVICES": return .bills
        case "MEDICAL", "PERSONAL_CARE": return .health
        case "ENTERTAINMENT": return .entertainment
        case "TRANSFER_IN", "TRANSFER_OUT", "LOAN_PAYMENTS", "INCOME", "LOAN_DISBURSEMENTS":
            return .transfer
        default: return .other
        }
    }

    /// Keyword guess for Apple Pay taps (no Plaid category available).
    static func guess(merchant: String) -> SpendCategory {
        let m = merchant.uppercased()
        let rules: [(SpendCategory, [String])] = [
            (.groceries, ["WHOLE FOODS", "TRADER JOE", "SAFEWAY", "KROGER", "ALDI", "COSTCO", "H MART", "STAR MARKET", "WEGMANS", "GROCER", "MARKET"]),
            (.dining, ["STARBUCKS", "DUNKIN", "CHIPOTLE", "MCDONALD", "SWEETGREEN", "CAFE", "COFFEE", "BAKERY", "PIZZA", "RESTAURANT", "BAR ", "GRILL", "KITCHEN", "TACO", "SUSHI", "RAMEN"]),
            (.transport, ["UBER", "LYFT", "MBTA", "AMTRAK", "SHELL", "EXXON", "CHEVRON", "MOBIL", "PARKING", "TRANSIT", "TOLL", "BLUEBIKES"]),
            (.health, ["CVS", "WALGREENS", "PHARMACY", "FITNESS", "GYM", "CLINIC"]),
            (.shopping, ["AMAZON", "TARGET", "WALMART", "BEST BUY", "APPLE STORE", "IKEA", "UNIQLO"]),
            (.travel, ["AIRLINES", "AIRBNB", "HOTEL", "MARRIOTT", "HILTON", "DELTA", "UNITED", "JETBLUE"]),
            (.entertainment, ["CINEMA", "THEATRE", "THEATER", "AMC", "TICKET"]),
        ]
        for (category, keywords) in rules where keywords.contains(where: { m.contains($0) }) {
            return category
        }
        return .other
    }
}

/// Remembers the user's merchant → category choices and applies them to
/// future charges from the same merchant.
enum CategoryMemory {
    private static let key = "categoryMemory"

    private static func normalized(_ merchant: String) -> String {
        merchant.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func remember(_ category: SpendCategory, for merchant: String) {
        var map = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        map[normalized(merchant)] = category.rawValue
        UserDefaults.standard.set(map, forKey: key)
    }

    static func lookup(_ merchant: String) -> SpendCategory? {
        let map = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        return map[normalized(merchant)].flatMap(SpendCategory.init(rawValue:))
    }
}
