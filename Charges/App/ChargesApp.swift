import SwiftData
import SwiftUI

@main
struct ChargesApp: App {
    @State private var sync = SyncEngine()
    @State private var link = LinkCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sync)
                .environment(link)
        }
        .modelContainer(DataStore.container)
        .backgroundTask(.appRefresh(AppConfig.backgroundTaskID)) {
            await BackgroundRefresh.run()
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SyncEngine.self) private var sync
    @Environment(LinkCoordinator.self) private var link
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        @Bindable var link = link
        TabView {
            NavigationStack { OverviewView() }
                .tabItem { Label("Overview", systemImage: "chart.bar.fill") }
            NavigationStack { ActivityView() }
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
            NavigationStack { AccountsView() }
                .tabItem { Label("Accounts", systemImage: "creditcard.fill") }
        }
        .sheet(isPresented: $link.isPresenting) {
            if let session = link.session {
                session.sheet()
            }
        }
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { onboarded = !$0 })) {
            WelcomeView()
        }
        .overlay(alignment: .bottom) { LinkStatusBanner() }
        .task {
            if AppConfig.hasCredentials { await sync.syncAll(context: context) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, AppConfig.hasCredentials {
                Task { await sync.syncAll(context: context) }
            } else if phase == .background {
                BackgroundRefresh.schedule()
            }
        }
        // Plaid's OAuth redirect (universal link) returns here; LinkKit resumes on its own.
        .onOpenURL { _ in }
    }
}

/// Floating status for the Link flow: importing / errors.
struct LinkStatusBanner: View {
    @Environment(LinkCoordinator.self) private var link

    var body: some View {
        Group {
            if link.isFinishing || link.isPreparing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(link.isFinishing ? "Importing your transactions…" : "Opening Plaid…")
                }
            } else if let message = link.errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(message).frame(maxWidth: .infinity, alignment: .leading)
                    Button { link.errorMessage = nil } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Dismiss")
                }
            }
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.bottom, 58)
        .opacity(link.isFinishing || link.isPreparing || link.errorMessage != nil ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: link.isFinishing)
    }
}

struct WelcomeView: View {
    @AppStorage("onboarded") private var onboarded = false
    @Environment(\.modelContext) private var context
    @State private var showSetup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Palette.blue, in: RoundedRectangle(cornerRadius: 16))
                    Text("Every card. Every charge.\nAutomatically.")
                        .font(.largeTitle.bold())
                    VStack(alignment: .leading, spacing: 14) {
                        bullet("building.columns.fill", "Your banks, your keys",
                               "Connect cards through your own free Plaid account — every swipe, tap, online order and subscription syncs on its own.")
                        bullet("lock.iphone", "Nothing leaves your iPhone",
                               "Charges has no server. Your keys and transactions stay on this device and go only to Plaid.")
                        bullet("wave.3.right", "Apple Card too",
                               "An optional Apple Pay automation logs taps instantly — the only way to track Apple Card.")
                    }
                    VStack(spacing: 10) {
                        Button { showSetup = true } label: {
                            Text("Connect my banks").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Button {
                            DemoData.setEnabled(true, context: context)
                            onboarded = true
                        } label: {
                            Text("Explore with demo data").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        Button("Skip for now") { onboarded = true }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
            .navigationDestination(isPresented: $showSetup) {
                PlaidSetupView(onDone: { onboarded = true })
            }
        }
    }

    private func bullet(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Palette.blue)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
