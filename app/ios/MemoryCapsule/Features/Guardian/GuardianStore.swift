import SwiftUI
import Observation

enum GuardianTab: Hashable { case today, alerts, schedules, settings }

/// 보호자 모드 상태. 흐름: G01 로그인 → G28 이름 → 동의(약관·일정) → G03 부모님 연결 → G24 → 탭(오늘/알림/약·일정/설정).
@Observable @MainActor
final class GuardianStore {
    enum Load: Equatable { case idle, loading, loaded, failed }
    enum Stage: Equatable { case auth, profile, consent, loadingLinks, linksError, link, main }

    var signedIn: Bool
    var guardianName: String? { didSet { defaults.set(guardianName, forKey: K.name) } }
    var consentDone: Bool { didSet { defaults.set(consentDone, forKey: K.consent) } }
    var prefs: NotificationPrefs {
        didSet { if let d = try? JSONEncoder().encode(prefs) { defaults.set(d, forKey: K.prefs) } }
    }
    var links: [GuardianLink] = []
    var linksState: Load = .idle
    var board: Board?
    var boardState: Load = .idle
    /// 보드를 불러오지 못한 이유(G11 문구 구분)
    var boardFailure: BoardFailure?
    var alerts: [Board.AlertItem] = []
    var schedules: [ScheduleItem] = []
    var tab: GuardianTab = .today

    @ObservationIgnored private let defaults = UserDefaults.standard
    private enum K {
        static let name = "mc.guardian.name", consent = "mc.consent.done.guardian", prefs = "mc.guardian.prefs"
        static let all = [name, consent, prefs]
    }

    init(auth: AuthService) {
        let d = UserDefaults.standard
        signedIn = auth.hasGuardianSession
        guardianName = d.string(forKey: K.name)
        consentDone = d.bool(forKey: K.consent)
        prefs = d.data(forKey: K.prefs).flatMap { try? JSONDecoder().decode(NotificationPrefs.self, from: $0) } ?? NotificationPrefs()
    }

    var stage: Stage {
        if !signedIn { return .auth }
        if guardianName == nil { return .profile }
        if !consentDone { return .consent }
        switch linksState {
        case .idle, .loading: return .loadingLinks
        case .failed: return .linksError
        case .loaded: return links.isEmpty ? .link : .main
        }
    }

    /// 지금 보는 부모님(여러 명 연결은 나중에. 지금은 첫 번째)
    var current: GuardianLink? { links.first }
    var seniorName: String { current?.displayName ?? board?.senior.displayName ?? "부모님" }
    var unreadAlerts: Int { alerts.filter { !Self.isRead($0) }.count }
    static func isRead(_ a: Board.AlertItem) -> Bool { a.deliveryStatus == "read" || a.deliveryStatus == "safety_checked" }

    // MARK: 계정

    func signedOut() {
        signedIn = false
        K.all.forEach(defaults.removeObject(forKey:))
        guardianName = nil; consentDone = false; prefs = NotificationPrefs()
        links = []; linksState = .idle; board = nil; boardState = .idle; alerts = []; schedules = []; tab = .today
    }

    func saveProfile(name: String, api: APIClient) async {
        guardianName = name
        await savePrefs(api)
    }

    /// G18 알림 설정(목 전용 필드 notification_prefs, 팀 서버는 무시)
    func savePrefs(_ api: APIClient) async {
        _ = try? await api.upsertMe(.init(role: .guardian, displayName: guardianName,
                                          timezone: TimeZone.current.identifier, notificationPrefs: prefs))
    }

    // MARK: 데이터

    func loadLinks(_ api: APIClient) async {
        linksState = .loading
        do { links = try await api.links(); linksState = .loaded } catch { linksState = .failed }
    }

    func loadBoard(_ api: APIClient) async {
        guard let id = current?.seniorId else { return }
        if board == nil { boardState = .loading }
        do {
            board = try await api.board(seniorId: id); boardState = .loaded; boardFailure = nil
        } catch {
            let failure = BoardFailure(error)
            boardFailure = failure
            // 동의·연결이 없어진 뒤에는 예전에 받은 내용을 계속 보여 주지 않는다
            if failure.hidesOldBoard { board = nil }
            boardState = .failed
        }
        await loadSchedules(api)
        await loadAlerts(api)
    }

    func loadAlerts(_ api: APIClient) async {
        guard let id = current?.seniorId else { return }
        if let list = try? await api.alerts(seniorId: id) {
            alerts = list.sorted { ($0.lastDetectedAt ?? .distantPast) > ($1.lastDetectedAt ?? .distantPast) }
        } else if let b = board {
            alerts = b.alertsRecent     // 알림 목록 API가 없으면 보드의 최근 알림만
        }
    }

    func markRead(_ alert: Board.AlertItem, api: APIClient) async {
        guard !Self.isRead(alert) else { return }
        try? await api.markAlertRead(id: alert.alertId)
        if let i = alerts.firstIndex(where: { $0.alertId == alert.alertId }) { alerts[i].deliveryStatus = "read" }
    }

    func followUp(_ alert: Board.AlertItem, status: String, api: APIClient) async throws {
        try await api.alertFollowUp(id: alert.alertId, status: status)
        if let i = alerts.firstIndex(where: { $0.alertId == alert.alertId }) {
            alerts[i].safetyFollowUpStatus = status
            if status == "verified" { alerts[i].deliveryStatus = "safety_checked" }   // 서버도 확인했을 때만 바꾼다
        }
    }

    func loadSchedules(_ api: APIClient) async {
        guard let id = current?.seniorId else { return }
        if let list = try? await api.schedules(seniorId: id) {
            schedules = list.sorted { $0.timeLocal < $1.timeLocal }
        }
    }

    func save(_ item: ScheduleItem, api: APIClient) async throws {
        var item = item
        if item.seniorId.isEmpty, let id = current?.seniorId { item.seniorId = id }
        _ = try await api.saveSchedule(item)
        await loadSchedules(api); await loadBoard(api)
    }

    func delete(_ item: ScheduleItem, api: APIClient) async throws {
        try await api.deleteSchedule(id: item.scheduleId)
        await loadSchedules(api); await loadBoard(api)
    }

    func unlink(_ api: APIClient) async throws {
        guard let link = current else { return }
        try await api.unlink(linkId: link.linkId)
        board = nil; boardState = .idle; alerts = []; schedules = []; tab = .today
        await loadLinks(api)
    }
}

/// 보호자 화면 문구 모음(명세 v0.6 Guardian_View 표시명 기준)
enum GuardianText {
    static func domain(_ d: String) -> String {
        ["depression": "우울 관련 신호", "anxiety": "불안 관련 신호", "addiction": "중독 관련 우려",
         "self_harm_suicide": "자해·안전 관련 신호", "other_crisis": "급성 혼란·행동 위기"][d] ?? d
    }
    static func level(_ l: RiskLevel?) -> String {
        switch l { case .r3: "긴급"; case .r2: "확인 필요"; case .r1: "관심"; default: "알림" }
    }
    static func intensity(_ i: String) -> String { ["LOW": "낮음", "MODERATE": "보통", "HIGH": "높음"][i] ?? i }
    static func trend(_ t: String?) -> String? {
        switch t { case "increasing": "늘고 있어요"; case "decreasing": "줄고 있어요"; case "stable": "비슷해요"; default: nil }
    }
    static func kind(_ item: ScheduleItem) -> String { item.isMedication ? "약" : "일정" }
    static func repeatText(_ rrule: String) -> String {
        if rrule == "NONE" { return "반복 없음" }
        if rrule == "FREQ=DAILY" { return "매일" }
        let map = ["MO": "월", "TU": "화", "WE": "수", "TH": "목", "FR": "금", "SA": "토", "SU": "일"]
        let days = rrule.components(separatedBy: "BYDAY=").dropFirst().first?.split(separator: ",").compactMap { map[String($0)] } ?? []
        return days.isEmpty ? rrule : "매주 " + days.joined(separator: "·")
    }
    static func status(_ s: String) -> (String, Color) {
        switch s { case "done": ("확인했어요", Theme.green); case "not_done": ("아직 확인 전", Theme.error); default: ("기록 없음", Theme.muted) }
    }
    private static let dayParser: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
    static func date(_ s: String?) -> Date? { s.flatMap { dayParser.date(from: $0) } }
    static func dateString(_ d: Date) -> String { dayParser.string(from: d) }
    /// "2026-11-08" → "8(일)"
    static func dayLabel(_ s: String) -> String {
        guard let d = date(s) else { return s }
        return d.formatted(.dateTime.day().locale(Locale(identifier: "ko_KR"))) + "(" +
            d.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "ko_KR"))) + ")"
    }
}

extension Board {
    /// 어르신이 마음 상태 공유(`sensitive`)에 동의했는지. 서버는 동의가 없으면 emotion_7d를 빈 객체로 보낸다
    /// (백엔드 착수 v0.6 2.8. 응답에 sharing 값이 생기면 그 값을 쓴다 — 작업 목록 N25).
    var emotionShared: Bool { sharing?.emotion ?? !emotion7d.isEmpty }
    /// 동의는 있는데 최근 7일 판단이 0건(서버는 네 값을 모두 0으로 보냄)
    var hasEmotionData: Bool { emotionShared && emotion7d.values.contains { $0 > 0 } }
    /// G10: 보여 줄 것이 아무것도 없음(동의는 있고 대화·일정·알림이 모두 없음)
    var isEmpty: Bool {
        emotionShared && !hasEmotionData && todaySchedules.isEmpty && alertsRecent.isEmpty
    }
}

/// 보드 요청이 실패한 이유. 서버(이현님 구현)는 동의·연결 문제를 403과 오류 코드로 알려 준다.
enum BoardFailure: Equatable {
    case consent            // 403 consent_required: 어르신 공유 동의 또는 보호자 동의 없음
    case notLinked          // 403 not_linked: 연결이 끊김
    case denied             // 그 밖의 403·404: 볼 권한 없음
    case network            // 서버에 닿지 못함
    case server(String)     // 서버 오류·응답 형식 문제

    init(_ error: Error) {
        if let api = error as? APIError {
            switch (api.status, api.code) {
            case (_, "consent_required"): self = .consent
            case (_, "not_linked"): self = .notLinked
            case (403, _), (404, _): self = .denied
            case (let status?, let code): self = .server("\(status) \(code ?? "")")
            default: self = .server("응답 형식")
            }
        } else if error is URLError { self = .network }
        else if let e = error as? DecodingError { self = .server("응답 형식 · " + Self.field(e)) }
        else { self = .network }
    }

    /// 읽지 못한 항목의 이름(내용은 담지 않는다). 개발용 빌드의 "원인:" 표시에만 쓴다.
    private static func field(_ error: DecodingError) -> String {
        func path(_ c: DecodingError.Context) -> String { c.codingPath.map(\.stringValue).joined(separator: ".") }
        switch error {
        case .keyNotFound(let key, let c): return "없음: " + (c.codingPath.map(\.stringValue) + [key.stringValue]).joined(separator: ".")
        case .valueNotFound(_, let c): return "비어 있음: " + path(c)
        case .typeMismatch(_, let c): return "형식 다름: " + path(c)
        case .dataCorrupted(let c): return "읽을 수 없음: " + path(c)
        @unknown default: return "알 수 없음"
        }
    }

    var hidesOldBoard: Bool { self == .consent || self == .notLinked || self == .denied }
    var icon: String {
        switch self {
        case .consent: "hand.raised"
        case .notLinked, .denied: "person.crop.circle.badge.exclamationmark"
        case .network: "wifi.exclamationmark"
        case .server: "exclamationmark.triangle"
        }
    }
    var title: String {
        switch self {
        case .consent: "아직 볼 수 없어요"
        case .notLinked: "연결이 끊겼어요"
        case .denied: "볼 수 있는 권한이 없어요"
        case .network: "연결을 확인해 주세요"
        case .server: "잠시 문제가 생겼어요"
        }
    }
    var message: String {
        switch self {
        case .consent: "부모님이 보호자와 나누기에 아직 동의하지 않으셨어요.\n부모님 앱의 보호자 연결 화면에서 동의하실 수 있어요."
        case .notLinked: "부모님과의 연결이 끊겼어요.\n설정에서 다시 연결해 주세요."
        case .denied: "부모님과의 연결 상태를 설정에서 확인해 주세요."
        case .network: "인터넷 연결을 확인하고 다시 불러와 주세요."
        case .server: "잠시 후 다시 불러와 주세요."
        }
    }
    /// 개발용 빌드에서만 보여 주는 원인
    var debugText: String? { if case .server(let detail) = self { detail } else { nil } }
}

enum GuardianNotice {
    static let emotionNotShared = "어르신이 마음 상태 공유에 아직 동의하지 않으셨어요.\n어르신 앱의 보호자 연결 화면에서 동의하실 수 있어요."
    static let noTalks = "최근 7일 동안 나눈 대화가 없어요."
}

extension ScheduleItem {
    static func blank(seniorId: String) -> ScheduleItem {
        let c = ConfigStore.shared.current.schedule
        return ScheduleItem(scheduleId: "", seniorId: seniorId, type: "medication", title: "", message: "",
                            rrule: "FREQ=DAILY", timeLocal: "08:00", timezone: "Asia/Seoul", needsAck: true,
                            reminderAfterMin: c.reminderAfterMinDefault, missedAfterMin: c.missedAfterMinDefault,
                            active: true, updatedAt: nil, startDate: GuardianText.dateString(.now))
    }
}
