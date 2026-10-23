import Foundation

/// Error body Plaid returns on any non-200 response.
struct PlaidAPIError: LocalizedError, Decodable {
    let errorType: String?
    let errorCode: String?
    let errorMessage: String?
    let displayMessage: String?

    var code: String { errorCode ?? "" }
    var errorDescription: String? { displayMessage ?? errorMessage ?? errorCode ?? "Plaid request failed" }

    /// Errors fixed by re-entering bank credentials through Link update mode.
    var needsReconnect: Bool {
        ["ITEM_LOGIN_REQUIRED", "PENDING_EXPIRATION", "PENDING_DISCONNECT", "ACCESS_NOT_GRANTED"].contains(code)
    }
}

enum PlaidClientError: LocalizedError {
    case missingCredentials
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: "Add your Plaid keys in Accounts → Plaid keys."
        case .badResponse(let status): "Unexpected response from Plaid (HTTP \(status))."
        }
    }
}

// MARK: - Response types (decoded with .convertFromSnakeCase)

struct LinkTokenResponse: Decodable { let linkToken: String }
struct ExchangeResponse: Decodable { let accessToken: String; let itemId: String }
struct ItemGetResponse: Decodable { let item: PlaidItem }
struct PlaidItem: Decodable { let itemId: String; let institutionId: String?; let institutionName: String? }
struct InstitutionResponse: Decodable { let institution: PlaidInstitution }
struct PlaidInstitution: Decodable { let institutionId: String; let name: String }
struct AccountsResponse: Decodable { let accounts: [PlaidAccount] }

struct PlaidAccount: Decodable {
    let accountId: String
    let name: String
    let officialName: String?
    let mask: String?
    let type: String
    let subtype: String?
}

struct SyncResponse: Decodable {
    let added: [PlaidTransaction]
    let modified: [PlaidTransaction]
    let removed: [RemovedTransaction]
    let nextCursor: String
    let hasMore: Bool
    let transactionsUpdateStatus: String?
    let accounts: [PlaidAccount]?
}

struct RemovedTransaction: Decodable { let transactionId: String }

struct PlaidTransaction: Decodable {
    let transactionId: String
    let accountId: String
    let amount: Double
    let isoCurrencyCode: String?
    let date: String
    let authorizedDate: String?
    let datetime: String?
    let authorizedDatetime: String?
    let name: String
    let merchantName: String?
    let logoUrl: String?
    let pending: Bool
    let pendingTransactionId: String?
    let personalFinanceCategory: PersonalFinanceCategory?
}

struct PersonalFinanceCategory: Decodable {
    let primary: String
    let detailed: String?
}

// MARK: - Client

/// Talks to Plaid directly from the device with the user's own keys.
struct PlaidClient {
    let environment: PlaidEnvironment
    let clientID: String
    let secret: String

    static func current() throws -> PlaidClient {
        let env = AppConfig.environment
        guard let id = AppConfig.clientID, let secret = AppConfig.secret(for: env) else {
            throw PlaidClientError.missingCredentials
        }
        return PlaidClient(environment: env, clientID: id, secret: secret)
    }

    /// New-bank Link token, or update-mode token when `accessToken` is given.
    func createLinkToken(accessToken: String? = nil) async throws -> String {
        var body: [String: Any] = [
            "client_name": "Billow",
            "language": "en",
            "country_codes": ["US"],
            "user": ["client_user_id": AppConfig.installID],
            "redirect_uri": AppConfig.redirectURI,
        ]
        if let accessToken {
            body["access_token"] = accessToken
        } else {
            body["products"] = ["transactions"]
            body["transactions"] = ["days_requested": 365]
        }
        let response: LinkTokenResponse = try await post("/link/token/create", body)
        return response.linkToken
    }

    func exchange(publicToken: String) async throws -> ExchangeResponse {
        try await post("/item/public_token/exchange", ["public_token": publicToken])
    }

    func item(accessToken: String) async throws -> PlaidItem {
        let response: ItemGetResponse = try await post("/item/get", ["access_token": accessToken])
        return response.item
    }

    func institutionName(id: String) async throws -> String {
        let response: InstitutionResponse = try await post(
            "/institutions/get_by_id", ["institution_id": id, "country_codes": ["US"]])
        return response.institution.name
    }

    func accounts(accessToken: String) async throws -> [PlaidAccount] {
        let response: AccountsResponse = try await post("/accounts/get", ["access_token": accessToken])
        return response.accounts
    }

    func sync(accessToken: String, cursor: String) async throws -> SyncResponse {
        var body: [String: Any] = ["access_token": accessToken, "count": 500]
        if !cursor.isEmpty { body["cursor"] = cursor }
        return try await post("/transactions/sync", body)
    }

    /// Asks Plaid to check the bank right now (results arrive via the next sync).
    func refresh(accessToken: String) async throws {
        let _: EmptyResponse = try await post("/transactions/refresh", ["access_token": accessToken])
    }

    /// Note: on the Trial plan this does NOT free up one of the 10 Item slots.
    func removeItem(accessToken: String) async throws {
        let _: EmptyResponse = try await post("/item/remove", ["access_token": accessToken])
    }

    private struct EmptyResponse: Decodable {}

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func post<Response: Decodable>(_ path: String, _ body: [String: Any]) async throws -> Response {
        var payload = body
        payload["client_id"] = clientID
        payload["secret"] = secret

        var request = URLRequest(url: environment.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2020-09-14", forHTTPHeaderField: "Plaid-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if let apiError = try? Self.decoder.decode(PlaidAPIError.self, from: data) { throw apiError }
            throw PlaidClientError.badResponse(status)
        }
        return try Self.decoder.decode(Response.self, from: data)
    }
}
