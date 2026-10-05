import BackgroundTasks
import SwiftData
import SwiftUI
import UserNotifications

@main
struct DoselyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var router = Router()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .onAppear {
                    NotificationService.shared.onOpenDose = { router.tab = .today }
                    #if DEBUG
                    DebugSupport.apply(router: router)
                    #endif
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    NotificationService.shared.requestReschedule()
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                    NotificationService.shared.requestReschedule()
                }
        }
        .modelContainer(DataStore.container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { NotificationService.shared.requestReschedule() }
        }
        .backgroundTask(.appRefresh(AppDelegate.refreshTaskID)) {
            await NotificationService.shared.rescheduleAll()
            await AppDelegate.scheduleRefresh()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    static let refreshTaskID = "com.jainil.dosely.refresh"

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Prefs.register()
        // The delegate must be set before launch finishes so actions from a cold start are delivered.
        MainActor.assumeIsolated {
            NotificationService.shared.configure()
        }
        Task { await Self.scheduleRefresh() }
        return true
    }

    @MainActor
    static func scheduleRefresh() async {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}

enum AppTab: Hashable {
    case today, medications, history, settings
}

@Observable
final class Router {
    var tab: AppTab = .today
    var showScan = false
    var showAddMedication = false
}
