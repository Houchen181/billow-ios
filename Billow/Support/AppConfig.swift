import Foundation

enum PlaidEnvironment: String, CaseIterable, Identifiable {
    case production
    case sandbox

    var id: String { rawValue }
    var baseURL: URL { URL(string: "https://\(rawValue).plaid.com")! }
    var label: String { self == .production ? "Production (your real banks)" : "Sandbox (fake test data)" }
}

/// Bring-your-own-keys configuration. Each user creates their own free Plaid
/// account; their client ID + secret stay in this device's Keychain and are
/// sent only to Plaid. There is no Billow server.
enum AppConfig {
    private static let envKey = "plaid.environment"

    static var environment: PlaidEnvironment {
        get { PlaidEnvironment(rawValue: UserDefaults.standard.string(forKey: envKey) ?? "") ?? .production }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: envKey) }
    }

    static var clientID: String? { Keychain.get("plaid.clientID") }

    static func secret(for env: PlaidEnvironment) -> String? {
        Keychain.get("plaid.secret.\(env.rawValue)")
    }

    static var hasCredentials: Bool {
        clientID != nil && secret(for: environment) != nil
    }

    static func saveCredentials(clientID: String, secret: String, env: PlaidEnvironment) {
        Keychain.set(clientID, for: "plaid.clientID")
        Keychain.set(secret, for: "plaid.secret.\(env.rawValue)")
        environment = env
    }

    static func accessTokenKey(itemID: String) -> String { "plaid.access.\(itemID)" }

    /// Host serving apple-app-site-association and the OAuth landing page (see site/).
    static var linkDomain: String {
        (Bundle.main.object(forInfoDictionaryKey: "BillowLinkDomain") as? String) ?? "billow-app.pages.dev"
    }

    /// Every user registers this exact URI in their own Plaid dashboard.
    static var redirectURI: String { "https://\(linkDomain)/plaid/oauth" }

    /// Stable per-install ID sent to Plaid as client_user_id (no personal data).
    static var installID: String {
        if let id = UserDefaults.standard.string(forKey: "installID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "installID")
        return id
    }

    static var backgroundTaskID: String {
        (Bundle.main.bundleIdentifier ?? "charges") + ".refresh"
    }
}
