import BackgroundTasks
import Foundation

/// iOS wakes the app periodically (its own schedule, typically every few
/// hours) to pull new charges and post notifications — no server needed.
enum BackgroundRefresh {
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: AppConfig.backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func run() async {
        schedule()      // keep the chain going
        guard AppConfig.hasCredentials else { return }
        let engine = SyncEngine()
        await engine.syncAll(context: DataStore.container.mainContext)
    }
}
