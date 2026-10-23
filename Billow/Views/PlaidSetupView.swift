import SwiftUI
import UIKit

/// Walks a user through creating their own free Plaid account and pasting
/// its keys. Keys are verified by creating a real Link token, which also
/// proves the redirect URI was registered.
struct PlaidSetupView: View {
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var clientID = AppConfig.clientID ?? ""
    @State private var secret = ""
    @State private var environment = AppConfig.environment
    @State private var checking = false
    @State private var resultText: String?
    @State private var succeeded = false
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                Text("Billow connects to your banks through **your own** Plaid account. Plaid's free Trial covers 10 bank logins with real data — plenty for one person. Takes about 10 minutes, once.")
                    .font(.subheadline)
            }

            Section("1 · Create a free Plaid account") {
                Link(destination: URL(string: "https://dashboard.plaid.com/signup")!) {
                    Label("Sign up at dashboard.plaid.com", systemImage: "arrow.up.right.square")
                }
                Link(destination: URL(string: "https://dashboard.plaid.com/trial-plan")!) {
                    Label("Apply for the free Trial plan", systemImage: "arrow.up.right.square")
                }
                Text("Use case: personal finance / expense tracking. Trial approval can take a little while.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text(AppConfig.redirectURI)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = AppConfig.redirectURI
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .accessibilityLabel("Copy redirect URI")
                }
            } header: {
                Text("2 · Allow this redirect URI")
            } footer: {
                Text("Plaid dashboard → Developers → API → Allowed redirect URIs → Add. Big banks (Chase, Amex, Capital One…) sign you in through their own page and need this.")
            }

            Section {
                Picker("Environment", selection: $environment) {
                    ForEach(PlaidEnvironment.allCases) { env in
                        Text(env.label).tag(env)
                    }
                }
                TextField("client_id", text: $clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                SecureField(environment == .production ? "Production secret" : "Sandbox secret", text: $secret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } header: {
                Text("3 · Paste your keys")
            } footer: {
                Text("Plaid dashboard → Developers → Keys. Stored only in this iPhone's Keychain and sent only to Plaid — Billow has no server.")
            }

            Section {
                Button {
                    Task { await verify() }
                } label: {
                    HStack {
                        Text("Verify & save")
                        Spacer()
                        if checking { ProgressView() }
                    }
                }
                .disabled(clientID.isEmpty || secret.isEmpty || checking)

                if let resultText {
                    Label(resultText, systemImage: succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Plaid keys")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func verify() async {
        checking = true
        defer { checking = false }
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await PlaidClient(environment: environment, clientID: id, secret: key).createLinkToken()
            AppConfig.saveCredentials(clientID: id, secret: key, env: environment)
            succeeded = true
            resultText = "Keys verified and saved. Next: Accounts → Link a bank."
            await Notifier.requestPermission()
            onDone?()
        } catch {
            succeeded = false
            resultText = LinkCoordinator.describe(error)
        }
    }
}

struct TapGuideView: View {
    var body: some View {
        List {
            Section {
                Text("Plaid can't read Apple Card. Instead, an iPhone automation can log every Apple Pay tap — on any card — the moment it happens. When the same purchase later arrives from your bank, Billow merges the two.")
                    .font(.subheadline)
            }
            Section("Set it up once (iOS 17+)") {
                step(1, "Open **Shortcuts** → **Automation** → **+** → **Transaction**.")
                step(2, "Select all your cards, leave the rest unfiltered, choose **Run Immediately**.")
                step(3, "**New Blank Automation** → add the **Log Card Tap** action (from Billow).")
                step(4, "Set **Amount** → Shortcut Input › Amount, **Merchant** → Shortcut Input › Merchant, **Card** → Shortcut Input › Card or Pass.")
                step(5, "Tap **Done**. Next time you tap to pay, it appears in Billow.")
                Link(destination: URL(string: "shortcuts://")!) {
                    Label("Open Shortcuts", systemImage: "arrow.up.right.square")
                }
            }
            Section("Good to know") {
                Text("Apple's trigger fires on in-store taps, not online Apple Pay. Developer forums report it occasionally times out — bank sync still catches those purchases for Plaid-linked cards.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Apple Pay taps")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Palette.blue, in: Circle())
            Text(text).font(.subheadline)
        }
    }
}
