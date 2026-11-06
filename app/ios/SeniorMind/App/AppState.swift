import SwiftUI
import UIKit
import Observation
import UserNotifications
import AVFoundation
#if canImport(FirebaseCore)
import FirebaseCore
#endif

/// 앱 전역 상태: 역할, 첫 실행 단계(동의 → 이름 → 권한), 의존성(API·인증·음성), 알람 화면.
/// 어르신과 보호자의 OS가 달라도 서버 계약만 맞으면 동작하도록 플랫폼 정보는 기기 등록에만 담는다.
@Observable @MainActor
final class AppState {
    static let shared = AppState()

    enum Phase: Equatable { case roleSelect, consent(UserRole), senior, guardian }

    var phase: Phase
    var userId: String?
    /// 어르신 호칭(S01에서 입력). 보호자 화면·알림에 쓰인다.
    var displayName: String? { didSet { defaults.set(displayName, forKey: Keys.name) } }
    var nameAsked: Bool { didSet { defaults.set(nameAsked, forKey: Keys.nameAsked) } }
    /// C02에서 마이크를 거절했으면 C03(마이크가 꺼져 있어요)을 먼저 보여 준다.
    var micDenied = false
    /// S13 말하는 속도(slow | normal)
    var speechRate: String { didSet { defaults.set(speechRate, forKey: Keys.speechRate) } }
    var birthYear: Int? { didSet { defaults.set(birthYear, forKey: Keys.birthYear) } }
    /// 연결된 보호자가 있는지(R3 화면의 "보호자에게 알렸어요" 표시용). 설정 화면이 갱신.
    var hasGuardian: Bool { didSet { defaults.set(hasGuardian, forKey: Keys.hasGuardian) } }
    /// 지금 울리는 알람(앱 안 알람 화면)
    var ringing: RingingAlarm?

    @ObservationIgnored let api: APIClient
    @ObservationIgnored let auth: AuthService
    @ObservationIgnored let deviceId: String
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let deviceId = "mc.device_id", role = "mc.role", name = "mc.display_name"
        static let nameAsked = "mc.name_asked", hasGuardian = "mc.has_guardian"
        static let speechRate = "mc.speech_rate", birthYear = "mc.birth_year"
        static func consentDone(_ r: UserRole) -> String { "mc.consent.done.\(r.rawValue)" }
    }

    private init() {
        let d = UserDefaults.standard
        if let id = d.string(forKey: Keys.deviceId) { deviceId = id } else {
            deviceId = UUID().uuidString; d.set(deviceId, forKey: Keys.deviceId)
        }
        displayName = d.string(forKey: Keys.name)
        nameAsked = d.bool(forKey: Keys.nameAsked)
        speechRate = d.string(forKey: Keys.speechRate) ?? "normal"
        birthYear = d.object(forKey: Keys.birthYear) as? Int
        hasGuardian = d.bool(forKey: Keys.hasGuardian)

        var appCheck: AppCheckService = NoAppCheck()
        #if canImport(FirebaseCore)
        if !AppInfo.useMock, Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil, FirebaseApp.app() == nil {
            #if canImport(FirebaseAppCheck)
            FirebaseAppCheckService.install()      // configure() 전에
            appCheck = FirebaseAppCheckService()
            #endif
            FirebaseApp.configure()
        }
        #endif
        #if canImport(FirebaseAuth)
        if !AppInfo.useMock && FirebaseAuthService.isConfigured { auth = FirebaseAuthService() } else { auth = MockAuthService() }
        #else
        auth = MockAuthService()
        #endif
        if AppInfo.useMock { api = MockAPIClient() } else {
            var http = HTTPAPIClient(baseURL: AppInfo.apiBaseURL, auth: auth)
            http.appCheck = appCheck
            api = http
        }

        switch d.string(forKey: Keys.role).flatMap(UserRole.init(rawValue:)) {
        case .senior: phase = d.bool(forKey: Keys.consentDone(.senior)) ? .senior : .consent(.senior)
        case .guardian: phase = d.bool(forKey: Keys.consentDone(.guardian)) ? .guardian : .consent(.guardian)
        case nil: phase = .roleSelect
        }
    }

    var role: UserRole? { defaults.string(forKey: Keys.role).flatMap(UserRole.init(rawValue:)) }

    func choose(_ role: UserRole) {
        defaults.set(role.rawValue, forKey: Keys.role)
        phase = .consent(role)
        Task { await bootstrap() }
    }

    /// C01 "확인하고 시작": 대화에 필요한 동의 3종 기록 → C02 마이크 권한 → C04로.
    func seniorConsentAccepted() async {
        for type in [ConsentType.voiceTransfer, .transcriptStore, .memoryCard] {
            defaults.set(true, forKey: "mc.consent.\(type.rawValue)")
            try? await api.postConsent(.init(type: type, version: ConsentStep.version, granted: true,
                                             method: "screen_tap", linkedSeniorId: nil))
        }
        micDenied = !(await AVAudioApplication.requestRecordPermission())
        consentFinished(.senior)
    }

    /// C01 "나중에": 역할 선택으로 돌아간다.
    func backToRoleSelect() {
        defaults.removeObject(forKey: Keys.role)
        phase = .roleSelect
    }

    func consentFinished(_ role: UserRole) {
        defaults.set(true, forKey: Keys.consentDone(role))
        phase = role == .senior ? .senior : .guardian
    }

    func makeLiveVoice() -> LiveVoice { AppInfo.useMock ? MockLiveVoice() : WebRTCLiveVoice() }

    /// 앱 시작 시: 계정 → 설정 → 기기 등록 → (어르신) 알람 동기화
    func bootstrap() async {
        guard let role else { return }
        if role == .senior { _ = try? await auth.signInSenior() }
        let profile = try? await api.upsertMe(.init(role: role, displayName: displayName, timezone: TimeZone.current.identifier,
                                                    birthYear: birthYear, speechRate: role == .senior ? speechRate : nil))
        userId = profile?.userId
        await ConfigStore.shared.refresh(using: api)
        await registerDevice(fcmToken: PushTokenStore.token)
        if role == .senior { await syncAlarms() }
    }

    /// C04 이름·나이(선택) 저장. 나이는 출생 연도로 바꿔 보낸다. 이어서 알림 권한을 묻는다.
    func saveName(_ name: String?, age: Int? = nil) async {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = (trimmed?.isEmpty ?? true) ? nil : trimmed
        if let age, (40...120).contains(age) {
            birthYear = Calendar.current.component(.year, from: .now) - age
        }
        nameAsked = true
        guard let role else { return }
        _ = try? await api.upsertMe(.init(role: role, displayName: displayName, timezone: TimeZone.current.identifier,
                                          birthYear: birthYear, speechRate: speechRate))
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await registerDevice(fcmToken: PushTokenStore.token)
    }

    /// S13 말하는 속도. 다음 대화부터 기억이 말투에 반영된다(서버가 지시문에 넣음).
    func setSpeechRate(_ rate: String) async {
        speechRate = rate
        guard let role else { return }
        _ = try? await api.upsertMe(.init(role: role, displayName: displayName, timezone: TimeZone.current.identifier,
                                          birthYear: birthYear, speechRate: rate))
    }

    func syncAlarms() async {
        guard let id = userId else { return }
        await AlarmScheduler.shared.sync(api: api, seniorId: id)
        checkRinging()
    }

    /// 앱이 앞에 있을 때 방금 울린 알람이 확인 전이면 앱 안 알람 화면을 띄운다.
    func checkRinging() {
        if ringing == nil { ringing = AlarmScheduler.shared.pendingRing(now: .now) }
    }

    /// 팀 문서 backend 6.1 기기 등록. 푸시 토큰·권한이 바뀔 때마다 다시 호출.
    func registerDevice(fcmToken: String?) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let notif: String = switch settings.authorizationStatus {
            case .authorized: "granted"; case .provisional, .ephemeral: "provisional"; case .denied: "denied"; default: "unknown"
        }
        let body = DeviceRegister(deviceId: deviceId, platform: "ios", appVersion: AppInfo.version,
                                  osVersion: UIDevice.current.systemVersion, fcmToken: fcmToken,
                                  notificationPermission: notif, alarmPermission: AlarmScheduler.shared.permissionString,
                                  locale: Locale.current.identifier, timezone: TimeZone.current.identifier)
        try? await api.registerDevice(body)
    }

    #if DEBUG
    /// 개발용: 처음 실행 상태로 되돌린다.
    func resetForDebug() {
        for key in [Keys.role, Keys.name, Keys.nameAsked, Keys.speechRate, Keys.birthYear, Keys.hasGuardian,
                    Keys.consentDone(.senior), Keys.consentDone(.guardian), "mc.consent.guardianShare"] {
            defaults.removeObject(forKey: key)
        }
        displayName = nil; nameAsked = false; hasGuardian = false; micDenied = false; speechRate = "normal"; birthYear = nil
        phase = .roleSelect
    }
    #endif
}

enum PushTokenStore {
    nonisolated(unsafe) static var token: String?
}
