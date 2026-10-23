import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SyncEngine {
    var isSyncing = false
    var lastError: String?
    var lastSynced: Date? = UserDefaults.standard.object(forKey: "lastSynced") as? Date

    private typealias NewCharge = (merchant: String, cents: Int, card: String, currency: String)

    /// Pulls every linked bank in the current environment.
    /// `refresh` first asks Plaid to re-check each bank (pull-to-refresh).
    func syncAll(context: ModelContext, refresh: Bool = false) async {
        guard !isSyncing, let client = try? PlaidClient.current() else { return }
        isSyncing = true
        defer { isSyncing = false }
        lastError = nil

        let env = client.environment.rawValue
        let banks = (try? context.fetch(FetchDescriptor<LinkedBank>(
            predicate: #Predicate { $0.environment == env }))) ?? []
        var fresh: [NewCharge] = []

        for bank in banks {
            guard let token = Keychain.get(AppConfig.accessTokenKey(itemID: bank.itemID)) else {
                bank.lastError = "Access token missing — remove and re-link this bank."
                continue
            }
            do {
                if refresh { try? await client.refresh(accessToken: token) }
                fresh += try await sync(bank: bank, token: token, client: client, context: context)
                bank.needsReconnect = false
                bank.lastError = nil
                bank.lastSynced = .now
            } catch let error as PlaidAPIError {
                bank.needsReconnect = error.needsReconnect
                bank.lastError = error.errorDescription
                lastError = "\(bank.institutionName): \(error.errorDescription ?? "sync failed")"
            } catch {
                bank.lastError = error.localizedDescription
                lastError = "\(bank.institutionName): \(error.localizedDescription)"
            }
        }
        try? context.save()
        Notifier.announce(fresh)
        lastSynced = .now
        UserDefaults.standard.set(lastSynced, forKey: "lastSynced")
    }

    /// Runs the /transactions/sync loop for one Item and applies the result.
    /// Returns charges worth announcing (never on the initial history pull).
    private func sync(bank: LinkedBank, token: String, client: PlaidClient,
                      context: ModelContext) async throws -> [NewCharge] {
        let isInitial = bank.cursor.isEmpty
        var attempt = 0
        while true {
            attempt += 1
            var cursor = bank.cursor
            var added: [PlaidTransaction] = []
            var modified: [PlaidTransaction] = []
            var removed: [String] = []
            var accounts: [PlaidAccount] = []
            do {
                var hasMore = true
                while hasMore {
                    let page = try await client.sync(accessToken: token, cursor: cursor)
                    added += page.added
                    modified += page.modified
                    removed += page.removed.map(\.transactionId)
                    if let pageAccounts = page.accounts { accounts += pageAccounts }
                    cursor = page.nextCursor
                    hasMore = page.hasMore
                }
            } catch let error as PlaidAPIError
                where error.code == "TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION" && attempt < 3 {
                continue    // restart the whole update from the original cursor
            }

            upsertAccounts(accounts, bank: bank, context: context)
            let announced = apply(added: added, modified: modified, removed: removed,
                                  bank: bank, context: context)
            bank.cursor = cursor
            return isInitial ? [] : announced
        }
    }

    private func apply(added: [PlaidTransaction], modified: [PlaidTransaction], removed: [String],
                       bank: LinkedBank, context: ModelContext) -> [NewCharge] {
        let itemID = bank.itemID
        let accounts = (try? context.fetch(FetchDescriptor<BankAccount>(
            predicate: #Predicate { $0.itemID == itemID }))) ?? []
        let labels = Dictionary(accounts.map { ($0.accountID, $0.label(institution: bank.institutionName)) },
                                uniquingKeysWith: { first, _ in first })
        let excluded = Set(accounts.filter { !$0.included }.map(\.accountID))

        // Pending rows get replaced by posted rows with new IDs: remember any
        // user edits so they carry over, and don't re-announce them.
        var carried: [String: (category: String, note: String)] = [:]
        var knownPending = Set<String>()
        for id in removed {
            guard let old = charge(id: id, context: context) else { continue }
            knownPending.insert(id)
            if old.userCategorized || !old.note.isEmpty { carried[id] = (old.categoryRaw, old.note) }
            context.delete(old)
        }

        var taps = (try? context.fetch(FetchDescriptor<Charge>(
            predicate: #Predicate { $0.source == "tap" }))) ?? []
        var announce: [NewCharge] = []

        for t in added + modified {
            let cents = Int((t.amount * 100).rounded())
            let date = Day.parsePlaid(datetime: t.authorizedDatetime ?? t.datetime,
                                      date: t.authorizedDate ?? t.date)
            let merchant = t.merchantName ?? t.name
            let category = SpendCategory.fromPlaid(primary: t.personalFinanceCategory?.primary,
                                                   detailed: t.personalFinanceCategory?.detailed)
            let card = labels[t.accountId] ?? bank.institutionName
            let currency = t.isoCurrencyCode ?? "USD"

            if let existing = charge(id: t.transactionId, context: context) {
                existing.amountCents = cents
                existing.date = date
                existing.merchant = merchant
                existing.rawName = t.name
                existing.pending = t.pending
                existing.logoURL = t.logoUrl
                existing.cardName = card
                if !existing.userCategorized { existing.category = category }
                continue
            }

            let new = Charge(id: t.transactionId, itemID: itemID, accountID: t.accountId, cardName: card,
                             date: date, amountCents: cents, currency: currency, merchant: merchant,
                             rawName: t.name, category: category, pending: t.pending,
                             source: "plaid", logoURL: t.logoUrl)
            if let pid = t.pendingTransactionId, let edit = carried[pid] {
                new.categoryRaw = edit.category
                new.userCategorized = true
                new.note = edit.note
            } else if let learned = CategoryMemory.lookup(merchant) {
                new.category = learned
            }
            context.insert(new)

            // An Apple Pay tap we logged earlier is the same purchase: merge it.
            var wasTapped = false
            if new.isSpending, cents > 0, let i = taps.firstIndex(where: { Self.matches(tap: $0, new) }) {
                let tap = taps.remove(at: i)
                if tap.userCategorized && !new.userCategorized {
                    new.categoryRaw = tap.categoryRaw
                    new.userCategorized = true
                }
                context.delete(tap)
                wasTapped = true
            }

            let isContinuation = t.pendingTransactionId.map { knownPending.contains($0) } ?? false
            if !wasTapped, !isContinuation, new.isSpending, cents > 0, !excluded.contains(t.accountId) {
                announce.append((merchant, cents, card, currency))
            }
        }
        return announce
    }

    /// Same amount within 4 days, or a shared merchant word with the amount
    /// within 25% inside 2 days (tips and adjustments change the final total).
    static func matches(tap: Charge, _ plaid: Charge) -> Bool {
        let days = abs(tap.date.timeIntervalSince(plaid.date)) / 86_400
        if tap.amountCents == plaid.amountCents && days <= 4 { return true }
        guard days <= 2, tap.amountCents > 0 else { return false }
        let ratio = Double(plaid.amountCents) / Double(tap.amountCents)
        guard ratio >= 0.8 && ratio <= 1.25 else { return false }
        let words = { (s: String) in
            Set(s.uppercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 4 })
        }
        return !words(tap.merchant).isDisjoint(with: words(plaid.merchant + " " + plaid.rawName))
    }

    private func upsertAccounts(_ accounts: [PlaidAccount], bank: LinkedBank, context: ModelContext) {
        for account in accounts {
            let id = account.accountId
            let existing = try? context.fetch(FetchDescriptor<BankAccount>(
                predicate: #Predicate { $0.accountID == id })).first
            if let existing {
                existing.name = account.name
                existing.mask = account.mask
            } else {
                context.insert(BankAccount(accountID: id, itemID: bank.itemID, name: account.name,
                                           mask: account.mask, type: account.type, subtype: account.subtype))
            }
        }
    }

    private func charge(id: String, context: ModelContext) -> Charge? {
        try? context.fetch(FetchDescriptor<Charge>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: - Linking

    /// Exchanges a Link public token, stores the access token in the Keychain,
    /// records the bank + its accounts, then pulls history (retrying while
    /// Plaid is still preparing the Item's first transactions).
    func finishLinking(publicToken: String, context: ModelContext) async throws {
        let client = try PlaidClient.current()
        let exchange = try await client.exchange(publicToken: publicToken)
        Keychain.set(exchange.accessToken, for: AppConfig.accessTokenKey(itemID: exchange.itemId))

        let item = try? await client.item(accessToken: exchange.accessToken)
        var name = item?.institutionName
        if name == nil, let institutionID = item?.institutionId {
            name = try? await client.institutionName(id: institutionID)
        }
        let bank = LinkedBank(itemID: exchange.itemId, institutionName: name ?? "Bank",
                              institutionID: item?.institutionId, environment: client.environment.rawValue)
        context.insert(bank)
        if let accounts = try? await client.accounts(accessToken: exchange.accessToken) {
            upsertAccounts(accounts, bank: bank, context: context)
        }
        try? context.save()

        for _ in 0..<6 {
            await syncAll(context: context)
            if !bank.cursor.isEmpty { break }
            try? await Task.sleep(for: .seconds(8))
        }
    }

    /// Deletes the bank, its accounts and its charges from this device.
    func unlink(_ bank: LinkedBank, context: ModelContext) async {
        let itemID = bank.itemID
        let key = AppConfig.accessTokenKey(itemID: itemID)
        if let token = Keychain.get(key), let client = try? PlaidClient.current() {
            try? await client.removeItem(accessToken: token)
        }
        Keychain.set(nil, for: key)
        let chargeItemID: String? = itemID
        let charges = (try? context.fetch(FetchDescriptor<Charge>(
            predicate: #Predicate { $0.itemID == chargeItemID }))) ?? []
        charges.forEach { context.delete($0) }
        let accounts = (try? context.fetch(FetchDescriptor<BankAccount>(
            predicate: #Predicate { $0.itemID == itemID }))) ?? []
        accounts.forEach { context.delete($0) }
        context.delete(bank)
        try? context.save()
    }
}
