import SwiftUI
import UserNotifications
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

@main
struct MemoryCapsuleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppState.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Theme.green)
                .task { await app.bootstrap() }
                .onOpenURL { url in DeepLink.handle(url) }
                .onChange(of: scenePhase) { _, phase in
                    // iOS는 무음 푸시를 보장하지 않으므로 포그라운드 복귀 때마다 동기화(iOS 대응표 1장 푸시)
                    if phase == .active, app.phase == .senior {
                        app.checkRinging()
                        Task { await app.syncAlarms() }
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        switch app.phase {
        case .roleSelect: RoleSelectView()
        case .consent(.senior): SeniorConsentView()
        case .consent(let role): ConsentFlowView(role: role)
        case .senior: SeniorRootView()
        case .guardian: GuardianRootView()
        }
    }
}

/// QR·딥링크. 두 OS 공통 형식(백엔드 6.3).
/// 형식: <scheme>://pair?v=1&code=123456
enum DeepLink {
    nonisolated(unsafe) static var pendingPairCode: String?
    static let schemes: Set<String> = ["memorycapsule"]

    static func parsePairCode(_ text: String) -> String? {
        if let comps = URLComponents(string: text), let scheme = comps.scheme, schemes.contains(scheme), comps.host == "pair",
           let code = comps.queryItems?.first(where: { $0.name == "code" })?.value, code.count == 6 { return code }
        let digits = text.filter(\.isNumber)
        return digits.count == 6 ? digits : nil
    }

    static func handle(_ url: URL) {
        if let code = parsePairCode(url.absoluteString) { pendingPairCode = code }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        #if canImport(FirebaseMessaging)
        if !AppInfo.useMock { Messaging.messaging().delegate = self }
        #endif
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if canImport(FirebaseMessaging)
        if !AppInfo.useMock { Messaging.messaging().apnsToken = deviceToken }
        #endif
    }

    /// 무음 푸시(type=schedules_updated 등). 전달이 보장되지 않으므로 보조 수단.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard let type = userInfo["type"] as? String else { return .noData }
        switch type {
        case "schedules_updated":
            let state = await MainActor.run { AppState.shared }
            await state.syncAlarms()
            return .newData
        case "pairing_done":
            await MainActor.run { NotificationCenter.default.post(name: .pairingDone, object: nil) }
            return .newData
        default: break
        }
        return .noData
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

#if canImport(FirebaseMessaging)
extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        PushTokenStore.token = fcmToken
        Task { await AppState.shared.registerDevice(fcmToken: fcmToken) }
    }
}
#endif

extension Notification.Name {
    static let pairingDone = Notification.Name("sm.pairingDone")
}
