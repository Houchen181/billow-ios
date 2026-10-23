import Foundation
import LinkKit
import Observation
import SwiftData

/// Drives one Plaid Link flow: token → session (preloads) → sheet → exchange.
/// Mirrors Plaid's LinkKit 7 SwiftUI sample (session-based API).
@MainActor
@Observable
final class LinkCoordinator {
    var session: PlaidLinkSession?
    var isPresenting = false
    var isPreparing = false
    var isFinishing = false
    var errorMessage: String?

    /// Starts linking a new bank, or reconnecting `bank` (update mode).
    func start(reconnecting bank: LinkedBank? = nil, context: ModelContext, sync: SyncEngine) async {
        guard !isPreparing else { return }
        errorMessage = nil
        isPreparing = true
        do {
            let client = try PlaidClient.current()
            var accessToken: String?
            if let bank {
                accessToken = Keychain.get(AppConfig.accessTokenKey(itemID: bank.itemID))
            }
            let token: String
            do {
                token = try await client.createLinkToken(accessToken: accessToken)
            } catch let error as PlaidAPIError where error.isRedirectProblem && client.environment == .sandbox {
                // Sandbox test banks don't need OAuth, so let testing work before the URI is registered.
                token = try await client.createLinkToken(accessToken: accessToken, includeRedirect: false)
            }

            let configuration = LinkTokenConfiguration(
                token: token,
                onSuccess: { [weak self] success in
                    let publicToken = success.publicToken
                    Task { @MainActor in
                        await self?.finish(publicToken: publicToken, reconnected: bank,
                                           context: context, sync: sync)
                    }
                },
                onExit: { [weak self] exit in
                    let message = exit.error?.displayMessage
                    Task { @MainActor in
                        self?.isPresenting = false
                        self?.isPreparing = false
                        if let message { self?.errorMessage = message }
                    }
                },
                onEvent: { _ in },
                onLoad: { [weak self] in
                    Task { @MainActor in
                        self?.isPreparing = false
                        self?.isPresenting = true
                    }
                }
            )
            session = try Plaid.createPlaidLinkSession(configuration: configuration)
        } catch {
            isPreparing = false
            errorMessage = Self.describe(error)
        }
    }

    private func finish(publicToken: String, reconnected bank: LinkedBank?,
                        context: ModelContext, sync: SyncEngine) async {
        isPresenting = false
        isFinishing = true
        defer { isFinishing = false; session = nil }
        if let bank {
            // Update mode keeps the same access token; just clear the flag and pull.
            bank.needsReconnect = false
            bank.lastError = nil
            await sync.syncAll(context: context, refresh: true)
            return
        }
        do {
            try await sync.finishLinking(publicToken: publicToken, context: context)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    static func describe(_ error: Error) -> String {
        if let plaid = error as? PlaidAPIError {
            if plaid.isRedirectProblem {
                return "Plaid rejected the redirect URI. Add \(AppConfig.redirectURI) under Developers → API → Allowed redirect URIs in your Plaid dashboard."
            }
            if plaid.code == "INVALID_API_KEYS" {
                return "Plaid didn't accept these keys. Check the client ID and the secret for the selected environment."
            }
            return plaid.errorDescription ?? "Plaid error \(plaid.code)"
        }
        return error.localizedDescription
    }
}
