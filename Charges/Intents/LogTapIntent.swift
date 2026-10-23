import AppIntents
import Foundation
import SwiftData

/// Called by a Shortcuts "Transaction" automation on every Apple Pay tap.
/// This is the only automatic channel for Apple Card (Plaid can't read it).
/// When the same purchase later arrives from Plaid, SyncEngine merges the two.
struct LogTapIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Card Tap"
    static let description = IntentDescription("Records an Apple Pay purchase in Charges.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Amount", description: "Shortcut Input → Amount")
    var amount: String

    @Parameter(title: "Merchant", description: "Shortcut Input → Merchant")
    var merchant: String?

    @Parameter(title: "Card", description: "Shortcut Input → Card or Pass")
    var card: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let cents = Money.parseCents(amount), cents > 0 else {
            return .result(dialog: "Charges couldn't read the amount “\(amount)”.")
        }
        let name = (merchant?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Apple Pay purchase"
        let context = DataStore.container.mainContext
        context.insert(Charge(
            id: "tap-\(UUID().uuidString)",
            cardName: card?.isEmpty == false ? card! : "Apple Pay",
            date: .now,
            amountCents: cents,
            merchant: name,
            category: CategoryMemory.lookup(name) ?? SpendCategory.guess(merchant: name),
            source: "tap"
        ))
        try context.save()
        return .result(dialog: "Logged \(Money.string(cents)) at \(name).")
    }
}

struct ChargesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogTapIntent(),
            phrases: ["Log a purchase in \(.applicationName)"],
            shortTitle: "Log Card Tap",
            systemImageName: "creditcard"
        )
    }
}
