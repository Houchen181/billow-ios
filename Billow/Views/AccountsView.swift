import SwiftData
import SwiftUI

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync
    @Environment(LinkCoordinator.self) private var link
    @Query(sort: \LinkedBank.createdAt) private var banks: [LinkedBank]
    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]

    @State private var hasKeys = AppConfig.hasCredentials
    @State private var environment = AppConfig.environment
    @State private var demoOn = DemoData.isEnabled
    @State private var notifyOn = Notifier.isEnabled
    @State private var removing: LinkedBank?

    private var currentBanks: [LinkedBank] {
        banks.filter { $0.environment == environment.rawValue }
    }

    var body: some View {
        List {
            Section {
                if !hasKeys {
                    NavigationLink {
                        PlaidSetupView(onDone: refreshState)
                    } label: {
                        Label("Set up bank sync (free)", systemImage: "building.columns")
                    }
                } else {
                    ForEach(currentBanks) { bank in
                        bankRow(bank)
                    }
                    Button {
                        Task { await link.start(context: context, sync: sync) }
                    } label: {
                        Label("Link a bank", systemImage: "plus.circle.fill")
                    }
                    .disabled(link.isPreparing || link.isFinishing)
                }
            } header: {
                Text("Banks")
            } footer: {
                if hasKeys && environment == .production {
                    Text("Your Plaid Trial includes 10 bank logins. Removing a bank does not give its slot back, so use Reconnect to fix a broken login.")
                }
            }

            Section("Apple Card & Apple Pay") {
                NavigationLink {
                    TapGuideView()
                } label: {
                    Label("Log Apple Pay taps automatically", systemImage: "wave.3.right")
                }
            }

            Section("Settings") {
                NavigationLink {
                    PlaidSetupView(onDone: refreshState)
                } label: {
                    LabeledContent("Plaid keys", value: hasKeys ? environment.label : "Not set")
                }
                Toggle("Notify me about new charges", isOn: $notifyOn)
                    .onChange(of: notifyOn) { _, on in
                        UserDefaults.standard.set(on, forKey: Notifier.enabledKey)
                        if on { Task { await Notifier.requestPermission() } }
                    }
                Toggle("Demo data", isOn: $demoOn)
                    .onChange(of: demoOn) { _, on in DemoData.setEnabled(on, context: context) }
            }

            Section("About") {
                Link(destination: URL(string: "https://\(AppConfig.linkDomain)/privacy")!) {
                    Label("Privacy policy", systemImage: "hand.raised")
                }
                Link(destination: URL(string: "https://\(AppConfig.linkDomain)/")!) {
                    Label("Help & setup guide", systemImage: "questionmark.circle")
                }
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
            }
        }
        .navigationTitle("Accounts")
        .refreshable { await sync.syncAll(context: context, refresh: true) }
        .onAppear(perform: refreshState)
        .confirmationDialog("Remove this bank?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible
        ) {
            Button("Remove bank and its charges", role: .destructive) {
                if let bank = removing {
                    Task { await sync.unlink(bank, context: context) }
                }
                removing = nil
            }
        } message: {
            Text("This deletes its charges from this iPhone. On the Plaid Trial, the bank's slot is NOT returned (10 total).")
        }
    }

    @ViewBuilder
    private func bankRow(_ bank: LinkedBank) -> some View {
        let bankAccounts = accounts.filter { $0.itemID == bank.itemID }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "building.columns.fill").foregroundStyle(Palette.blue)
                Text(bank.institutionName).font(.headline)
                Spacer()
                if bank.needsReconnect {
                    Button("Reconnect") {
                        Task { await link.start(reconnecting: bank, context: context, sync: sync) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            if let error = bank.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let last = bank.lastSynced {
                Text("Synced \(last.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Waiting for the first transactions from Plaid…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(bankAccounts) { account in
                Toggle(isOn: Binding(get: { account.included }, set: { on in
                    account.included = on
                    try? context.save()
                })) {
                    VStack(alignment: .leading) {
                        Text(account.name).font(.subheadline)
                        Text([account.subtype ?? account.type, account.mask.map { "•\($0)" }]
                            .compactMap { $0 }.joined(separator: " "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions {
            Button("Remove", role: .destructive) { removing = bank }
        }
    }

    private func refreshState() {
        hasKeys = AppConfig.hasCredentials
        environment = AppConfig.environment
        demoOn = DemoData.isEnabled
    }
}
