import SwiftUI
import UserNotifications
import LocalAuthentication

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor static var openPurchase: (@MainActor (UUID) -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let s = response.notification.request.content.userInfo["purchaseID"] as? String, let id = UUID(uuidString: s) {
            await MainActor.run { AppDelegate.openPurchase?(id) }
        }
    }
}

@main
struct ReturnMateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: DataStore
    @State private var router = Router()
    @State private var locked: Bool
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let defaults = UserDefaults.standard
        let s: DataStore
        if defaults.bool(forKey: "demoData") {
            s = DataStore(inMemory: true, initial: DemoData.make())
        } else {
            s = DataStore()
        }
        _store = State(initialValue: s)
        _locked = State(initialValue: s.settings.appLock)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if store.data.profile == nil {
                    OnboardingView()
                } else if locked {
                    LockView { locked = false }
                } else {
                    RootView()
                }
            }
            .environment(store)
            .environment(router)
            .environment(NotificationManager.shared)
            .environment(PremiumManager.shared)
            .tint(Color("AccentColor"))
            .task {
                AppDelegate.openPurchase = { id in router.open(id) }
                await NotificationManager.shared.refreshStatus()
                store.rescheduleReminders()
                router.applyLaunchScreen()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background && store.settings.appLock { locked = true }
                if phase == .active { Task { await NotificationManager.shared.refreshStatus() } }
            }
        }
    }
}

enum AppTab: Hashable {
    case home, calendar, search, stats, settings
}

@MainActor
@Observable
final class Router {
    var tab: AppTab = .home
    var homePath = NavigationPath()
    var calendarPath = NavigationPath()
    var searchPath = NavigationPath()
    var showAdd = false
    var launchScreen: String?

    func open(_ id: UUID) {
        tab = .home
        homePath = NavigationPath()
        homePath.append(PurchaseRoute(id: id))
    }

    /// Usato solo per generare gli screenshot automatici (argomento di avvio "-screen").
    func applyLaunchScreen() {
        guard let screen = UserDefaults.standard.string(forKey: "screen") else { return }
        launchScreen = screen
        switch screen {
        case "calendar": tab = .calendar
        case "search": tab = .search
        case "stats": tab = .stats
        case "settings", "premium": tab = .settings
        case "add", "confirm": showAdd = true
        case "detail", "returnflow":
            if let id = DemoData.featuredID { open(id) }
        default: tab = .home
        }
    }
}

struct LockView: View {
    let onUnlock: () -> Void
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield.fill").font(.system(size: 64)).foregroundStyle(Color.accentColor)
            Text("ReturnMate è bloccata").font(.title2.bold())
            if let error { Text(error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            Button("Sblocca") { authenticate() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
        .onAppear(perform: authenticate)
    }

    private func authenticate() {
        let context = LAContext()
        var err: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // Nessun codice o biometria configurati: non si può bloccare.
            onUnlock()
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Accedi ai tuoi acquisti") { ok, e in
            DispatchQueue.main.async {
                if ok { onUnlock() } else { error = e?.localizedDescription }
            }
        }
    }
}
