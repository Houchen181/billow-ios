import Foundation
import UserNotifications

enum Notifier {
    static let enabledKey = "notify.newCharges"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// One banner per new charge; collapses into a summary past five.
    static func announce(_ charges: [(merchant: String, cents: Int, card: String, currency: String)]) {
        guard isEnabled, !charges.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        if charges.count > 5 {
            let total = charges.reduce(0) { $0 + $1.cents }
            let content = UNMutableNotificationContent()
            content.title = "\(charges.count) new charges"
            content.body = "\(Money.string(total)) across your cards"
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            return
        }
        for charge in charges {
            let content = UNMutableNotificationContent()
            content.title = "\(Money.string(charge.cents, currency: charge.currency)) · \(charge.merchant)"
            content.body = charge.card
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
