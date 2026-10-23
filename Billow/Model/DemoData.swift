import Foundation
import SwiftData

/// Deterministic sample data (source "demo") so the app can be explored —
/// including by App Review — without linking a bank.
@MainActor
enum DemoData {
    static let enabledKey = "demo.enabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static func setEnabled(_ on: Bool, context: ModelContext) {
        UserDefaults.standard.set(on, forKey: enabledKey)
        remove(context: context)
        if on { install(context: context) }
        try? context.save()
    }

    private static func remove(context: ModelContext) {
        let demos = (try? context.fetch(FetchDescriptor<Charge>(
            predicate: #Predicate { $0.source == "demo" }))) ?? []
        demos.forEach { context.delete($0) }
    }

    private static func install(context: ModelContext) {
        var rng = SeededRandom(seed: 20261022)
        // Made-up names only: demo data appears in App Store screenshots and
        // review, where real brands and card issuers would be trademark issues.
        let cards = ["Travel Card •4321", "Cashback Card •1005", "Everyday Card •2210"]
        let pool: [(String, SpendCategory, Double, Double, Double)] = [
            ("Bluebird Coffee", .dining, 4.5, 9, 0.16),
            ("Greenleaf Salads", .dining, 12, 18, 0.10),
            ("Sunrise Donuts", .dining, 3.5, 7, 0.10),
            ("Harbor Market", .groceries, 18, 85, 0.10),
            ("Golden Lotus Grocery", .groceries, 15, 70, 0.06),
            ("City Transit", .transport, 2.4, 10, 0.11),
            ("QuickRide", .transport, 9, 34, 0.06),
            ("ShopNow Online", .shopping, 8, 120, 0.09),
            ("Everyday Mart", .shopping, 12, 90, 0.05),
            ("Corner Pharmacy", .health, 6, 40, 0.05),
            ("Starlight Cinemas", .entertainment, 14, 32, 0.03),
            ("SkyHigh Airways", .travel, 180, 420, 0.01),
        ]
        let subscriptions: [(String, Int, Int)] = [("StreamBox", 1549, 3), ("TuneWave Music", 1199, 9), ("Cloud Storage", 299, 12)]
        let calendar = Calendar.current
        let totalWeight = pool.reduce(0) { $0 + $1.4 }
        var n = 0

        func make(_ merchant: String, _ category: SpendCategory, _ cents: Int, _ card: String,
                  _ day: Date, hour: Int) -> Charge {
            n += 1
            let date = calendar.date(byAdding: .hour, value: hour, to: day) ?? day
            return Charge(id: "demo-\(n)", cardName: card, date: date, amountCents: cents,
                          merchant: merchant, category: category, source: "demo")
        }

        for offset in stride(from: 59, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Day.start(.now)) else { continue }
            let dom = calendar.component(.day, from: day)
            for (name, cents, billingDay) in subscriptions where billingDay == dom {
                context.insert(make(name, .bills, cents, cards[1], day, hour: 7))
            }
            let weekend = calendar.isDateInWeekend(day)
            var count = Int(rng.next() * (weekend ? 4.4 : 3.1))
            if offset == 0 { count = max(count, 2) }
            for _ in 0..<count {
                var roll = rng.next() * totalWeight
                var pick = pool[0]
                for entry in pool {
                    roll -= entry.4
                    if roll <= 0 { pick = entry; break }
                }
                let cents = Int(((pick.2 + rng.next() * (pick.3 - pick.2)) * 100).rounded())
                let card = cards[Int(rng.next() * Double(cards.count)) % cards.count]
                context.insert(make(pick.0, pick.1, cents, card, day, hour: 8 + Int(rng.next() * 13)))
            }
        }
    }
}

/// Small deterministic PRNG (SplitMix64) returning values in [0, 1).
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
