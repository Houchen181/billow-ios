import Foundation
import SwiftData

/// One card transaction. Named `Charge` (not `Transaction`) to avoid clashing
/// with SwiftUI.Transaction.
@Model
final class Charge {
    /// Plaid transaction_id, or "tap-…"/"demo-…" for other sources.
    @Attribute(.unique) var id: String
    var itemID: String?
    var accountID: String?
    var cardName: String
    var date: Date
    /// Positive = money spent; negative = refund/credit.
    var amountCents: Int
    var currency: String
    var merchant: String
    var rawName: String
    var categoryRaw: String
    var userCategorized: Bool
    var pending: Bool
    /// "plaid" | "tap" | "demo"
    var source: String
    var logoURL: String?
    var note: String
    var createdAt: Date

    init(id: String, itemID: String? = nil, accountID: String? = nil, cardName: String,
         date: Date, amountCents: Int, currency: String = "USD", merchant: String,
         rawName: String? = nil, category: SpendCategory, pending: Bool = false,
         source: String, logoURL: String? = nil) {
        self.id = id
        self.itemID = itemID
        self.accountID = accountID
        self.cardName = cardName
        self.date = date
        self.amountCents = amountCents
        self.currency = currency
        self.merchant = merchant
        self.rawName = rawName ?? merchant
        self.categoryRaw = category.rawValue
        self.userCategorized = false
        self.pending = pending
        self.source = source
        self.logoURL = logoURL
        self.note = ""
        self.createdAt = .now
    }

    var category: SpendCategory {
        get { SpendCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var isSpending: Bool { category.countsAsSpending }
}

/// One Plaid Item = one login at one bank (may hold several cards).
@Model
final class LinkedBank {
    @Attribute(.unique) var itemID: String
    var institutionName: String
    var institutionID: String?
    /// PlaidEnvironment raw value the Item was created in.
    var environment: String
    /// /transactions/sync cursor; empty until the first page arrives.
    var cursor: String
    var lastSynced: Date?
    var needsReconnect: Bool
    var lastError: String?
    var createdAt: Date

    init(itemID: String, institutionName: String, institutionID: String?, environment: String) {
        self.itemID = itemID
        self.institutionName = institutionName
        self.institutionID = institutionID
        self.environment = environment
        self.cursor = ""
        self.needsReconnect = false
        self.createdAt = .now
    }
}

@Model
final class BankAccount {
    @Attribute(.unique) var accountID: String
    var itemID: String
    var name: String
    var mask: String?
    var type: String
    var subtype: String?
    /// Credit cards are tracked by default; checking/savings are opt-in.
    var included: Bool

    init(accountID: String, itemID: String, name: String, mask: String?, type: String, subtype: String?) {
        self.accountID = accountID
        self.itemID = itemID
        self.name = name
        self.mask = mask
        self.type = type
        self.subtype = subtype
        self.included = (type == "credit")
    }

    func label(institution: String) -> String {
        if let mask, !mask.isEmpty { return "\(institution) •\(mask)" }
        return "\(institution) \(name)"
    }
}

@MainActor
enum DataStore {
    static let container: ModelContainer = {
        let schema = Schema([Charge.self, LinkedBank.self, BankAccount.self])
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            fatalError("Could not open the Billow store: \(error)")
        }
    }()
}
