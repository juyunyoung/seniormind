import Foundation

// 서버 계약은 팀 문서 backend_spec v0.4.3(6장 크로스 플랫폼 공통 계약)을 따른다. Android 앱과 같은 값을 쓴다.

enum UserRole: String, Codable, Sendable { case senior, guardian }

/// PoC reactions.mjs와 같은 6종. 서버 `/api/decision` 응답의 `reaction`.
enum Reaction: String, Codable, Sendable, CaseIterable {
    case hold, neutral, happy, empathy
    case surprisedHappy = "surprised_happy"
    case surprisedConcern = "surprised_concern"
}

/// 캐릭터 표정 4종(PoC character.mjs poses).
enum Expression: String, CaseIterable, Sendable {
    case neutral, happy, empathy, surprised

    var title: String {
        switch self {
        case .neutral: "기본"
        case .happy: "기쁨"
        case .empathy: "공감"
        case .surprised: "놀람"
        }
    }
    /// PoC app.mjs labels
    var label: String {
        switch self {
        case .neutral: "편안하게 듣기"
        case .happy: "함께 웃기"
        case .empathy: "조용히 공감하기"
        case .surprised: "살짝 놀라기"
        }
    }
    var subtitle: String {
        switch self {
        case .neutral: "편안하게 듣기"
        case .happy: "함께 웃기"
        case .empathy: "조용히 마음 쓰기"
        case .surprised: "눈을 동그랗게"
        }
    }
}

enum RiskLevel: String, Codable, Sendable {
    case r0 = "R0", r1 = "R1", r2 = "R2", r3 = "R3", unknown
}

enum MemoryControl: String, Codable, Sendable {
    case none = "NONE", delete = "DELETE", doNotRemember = "DO_NOT_REMEMBER"
    case doNotShare = "DO_NOT_SHARE", correct = "CORRECT"
}

enum ConsentType: String, Codable, Sendable, CaseIterable {
    // 어르신
    case voiceTransfer = "voice_transfer", transcriptStore = "transcript_store", memoryCard = "memory_card"
    case sensitive, guardianShare = "guardian_share", scheduleShare = "schedule_share"
    case guardianTopicShare = "guardian_topic_share"
    // 보호자
    case guardianTerms = "guardian_terms", guardianDataView = "guardian_data_view"
    case guardianScheduleManage = "guardian_schedule_manage"
}

// MARK: - 계정·기기

struct UserUpsert: Codable, Sendable {
    var role: UserRole
    var displayName: String?
    var timezone: String
    /// 시니어 C04 나이(선택) → 출생 연도. 없으면 보내지 않는다.
    var birthYear: Int? = nil
    /// 시니어 S13 말하는 속도: slow | normal
    var speechRate: String? = nil
    /// 보호자 G18 신호 알림 설정(보낸 키만 병합)
    var notificationPrefs: NotificationPrefs? = nil
}

/// 보호자 알림 설정(백엔드 1.0, users.notification_prefs). R3는 설정과 무관하게 항상 받는다.
struct NotificationPrefs: Codable, Sendable, Equatable {
    var riskMinLevel: String? = "R2"     // R2 | R3
    var scheduleMissed: Bool? = true
    var weeklyReport: Bool? = true
}

/// 보호자가 QR·번호로 연결 전에 대상 어르신을 확인(G24). 팀 서버 미구현 — 작업 목록 N21 제안 계약.
struct PairingTarget: Codable, Sendable {
    var seniorId: String
    var displayName: String?
    var expiresAt: Date?
}

struct UserProfile: Codable, Sendable {
    var userId: String
    var role: UserRole
    var displayName: String?
    var timezone: String
}

/// backend_spec v0.4 6.1 — 기기 단위 등록(어르신·보호자 OS가 달라도 서버가 기기별로 푸시를 나눔)
struct DeviceRegister: Codable, Sendable {
    var deviceId: String
    var platform: String          // "ios" | "android"
    var appVersion: String
    var osVersion: String
    var fcmToken: String?
    var notificationPermission: String  // granted | denied | provisional | unknown
    var alarmPermission: String         // granted | denied | unknown
    var locale: String
    var timezone: String
}

struct ConsentRequest: Codable, Sendable {
    var type: ConsentType
    var version: String
    var granted: Bool
    var method: String           // screen_tap | voice_confirm
    var linkedSeniorId: String?
}

// MARK: - 설정

struct SafetyPhrase: Codable, Sendable { var id: String; var level: RiskLevel; var text: String; var numbers: [String]? }
struct Hotline: Codable, Sendable { var name: String; var number: String }
struct Contact: Codable, Sendable { var number: String; var name: String; var use: String }

struct AppConfig: Codable, Sendable {
    struct Safety: Codable, Sendable {
        var phrases: [SafetyPhrase]
        var hotline: Hotline
        var contacts: [Contact]?
        var actions: [String: String]      // R1/R2/R3 → 코드(CHECK_IN …)
        var actionText: [String: String]?  // 코드 → 안내 문구
    }
    struct Session: Codable, Sendable { var maxSeconds: Int; var dailyLimit: Int }
    struct Decision: Codable, Sendable { var batchMs: Int; var maxInputChars: Int }
    struct Schedule: Codable, Sendable {
        var reminderAfterMinDefault: Int
        var missedAfterMinDefault: Int
        var maxReminders: Int
        var alarmHorizonHours: Int
    }
    struct Pricing: Codable, Sendable { var livePerMinUsd: Double; var decisionPerMtokUsd: Double }

    var configVersion: String
    var safety: Safety
    var session: Session
    var decision: Decision
    var schedule: Schedule
    var pricing: Pricing

    /// 서버 설정을 못 받을 때 쓰는 앱 내장 기본값(데이터 담당 D3 확정본으로 릴리스마다 갱신).
    static let builtIn = AppConfig(
        configVersion: "builtin-2026.10.25",
        safety: .init(
            // 데이터 명세 v0.6 config_safety · Crisis_Response (서버 설정으로 덮어씀)
            phrases: [
                .init(id: "R2_CHECK_IN", level: .r2, text: "최근 마음이나 생활에 어려움이 있을 수 있어요. 괜찮으시다면 지금 기분과 필요한 도움을 함께 살펴볼까요?", numbers: []),
                .init(id: "R2_SUPPORT", level: .r2, text: "혼자 감당하지 않으셔도 괜찮아요. 믿을 만한 가족이나 전문가에게 연락해 도움을 요청하실 수 있어요.", numbers: ["1577-0199"]),
                .init(id: "SAFE_SUICIDE_R2", level: .r2, text: "힘든 마음을 말씀해 주셔서 감사합니다. 혼자 감당하지 않으셔도 됩니다. 지금 안전한 곳에 계신가요? 도움이 필요하시면 자살예방상담전화 109에 연락할 수 있어요.", numbers: ["109"]),
                .init(id: "SAFE_ANXIETY", level: .r2, text: "매우 불안하고 힘드시겠어요. 지금 안전한 장소에 계신지 확인해 주세요. 불안이 계속되면 정신건강상담전화 1577-0199에서 도움을 받을 수 있습니다. 숨쉬기 어렵거나 심한 가슴 통증이 있다면 119로 연락해 주세요.", numbers: ["1577-0199", "119"]),
                .init(id: "R3_SAFETY_CHECK", level: .r3, text: "지금 안전이 가장 중요합니다. 현재 안전한 곳에 계신가요? 가까운 믿을 만한 사람에게 바로 도움을 요청해 주세요.", numbers: ["119"]),
                .init(id: "R3_CRISIS_HELP", level: .r3, text: "지금 위험하다고 느끼신다면 혼자 계시지 마시고 즉시 119에 연락하거나 가까운 응급실에서 도움을 받으세요.", numbers: ["119"]),
                .init(id: "R3_SUICIDE_SUPPORT", level: .r3, text: "죽음이나 자해에 관한 생각 때문에 힘드시다면 지금 바로 도움을 요청해 주세요. 자살예방상담전화 109에서 상담받으실 수 있습니다. 즉각적인 위험이 있다면 119에 연락해 주세요.", numbers: ["109", "119"]),
                .init(id: "SAFE_SUICIDE_R3", level: .r3, text: "지금은 안전을 확인하는 것이 가장 중요합니다. 혼자 계시다면 가까운 사람에게 바로 도움을 요청해 주세요. 위험이 임박했다면 지금 119에 연락해 주세요. 자살예방상담전화 109에서도 도움을 받을 수 있습니다.", numbers: ["119", "109"]),
                .init(id: "SAFE_CONFUSION", level: .r3, text: "갑자기 시간이나 장소를 알아보기 어렵거나 평소와 다르게 혼란스럽다면 즉시 의료적 확인이 필요할 수 있습니다. 지금 119에 연락하고 가까운 사람에게 도움을 요청해 주세요.", numbers: ["119"]),
                .init(id: "SAFE_BEHAVIOR", level: .r3, text: "지금 신변에 위협이 있다면 우선 안전한 장소로 이동하고 경찰 112에 연락해 주세요. 다치거나 응급진료가 필요하면 119에 연락해 주세요.", numbers: ["112", "119"]),
                .init(id: "SAFE_MEDICATION", level: .r3, text: "약을 평소보다 많이 드셨거나 복용 후 의식이 흐려진다면 응급상황일 수 있습니다. 지금 바로 119에 연락해 주세요.", numbers: ["119"]),
            ],
            hotline: .init(name: "자살예방상담전화", number: "109"),
            contacts: [.init(number: "109", name: "자살예방상담전화", use: "자살 위기 상담"),
                       .init(number: "119", name: "구급·화재 긴급신고", use: "응급 의학적 위험"),
                       .init(number: "112", name: "경찰 긴급신고", use: "신변 위협·폭력"),
                       .init(number: "1577-0199", name: "정신건강상담전화", use: "정서 위기 상담")],
            actions: ["R1": "CHECK_IN", "R2": "PROMPT_CONTACT", "R3": "URGENT_SAFETY_CHECK"],
            actionText: ["CHECK_IN": "일상적인 안부를 확인해 주세요.",
                         "PROMPT_CONTACT": "적극적으로 안부를 확인하고, 필요하면 상담을 연결해 주세요.",
                         "URGENT_SAFETY_CHECK": "지금 바로 안전을 확인하고, 응급 대응을 연결해 주세요."]),
        session: .init(maxSeconds: 600, dailyLimit: 6),
        decision: .init(batchMs: 1000, maxInputChars: 1600),
        schedule: .init(reminderAfterMinDefault: 10, missedAfterMinDefault: 60, maxReminders: 3, alarmHorizonHours: 48),
        pricing: .init(livePerMinUsd: 0.05, decisionPerMtokUsd: 0.10))
}

struct ConfigResponse: Codable, Sendable {
    var configVersion: String
    var config: AppConfig
    var signature: String?
}

// MARK: - 세션·판단

struct SessionCreateRequest: Codable, Sendable {
    struct Client: Codable, Sendable { var platform: String; var appVersion: String }
    var sdp: String
    var client: Client
}

struct SessionCreateResponse: Codable, Sendable {
    struct Session: Codable, Sendable { var id: String; var maxSeconds: Int }
    struct Transport: Codable, Sendable { var type: String; var sdp: String }
    var session: Session
    var transport: Transport
}

struct Utterance: Codable, Sendable { var text: String; var startMs: Int; var endMs: Int }

struct DecisionRequest: Codable, Sendable {
    var sessionId: String
    var utteranceId: String
    var inputText: String
    var outputText: String
    var previousReaction: Reaction
    var final: Bool
    var utterance: Utterance?
}

struct DecisionResponse: Codable, Sendable {
    struct Usage: Codable, Sendable { var inputTokens: Int? }
    var reaction: Reaction
    var riskLevel: RiskLevel
    var assessmentStatus: String?      // assessed | needs_review | unavailable
    /// true면 서버가 reaction을 empathy로 고정해 보낸 것(안전 문구 재생 중). 자동 전환 금지.
    var safetyOverride: Bool?
    var safetyPhraseId: String?
    var memoryControl: MemoryControl
    var assessmentId: String?
    var usage: Usage?
    var latencyMs: Int?
}

struct TranscriptPart: Codable, Sendable {
    var direction: String     // input | output
    var utteranceId: String?
    var text: String
    var startMs: Int
    var endMs: Int
}

struct SessionEndRequest: Codable, Sendable {
    struct Usage: Codable, Sendable { var seconds: Int? }
    var endReason: String     // user | limit | error
    var durationSec: Int
    var usage: Usage
    var transcript: [TranscriptPart]
}

struct MemoryControlRequest: Codable, Sendable {
    var assessmentId: String
    var confirmed: Bool
    var scope: String
    var targetCardIds: [String]
}

// MARK: - 보호자·일정

struct PairingCode: Codable, Sendable {
    var code: String
    var expiresAt: Date
    /// 서버가 만든 QR 문자열. 예: memorycapsule://pair?v=1&code=123456 (두 OS 공통)
    var qrPayload: String
}

struct GuardianLink: Codable, Sendable, Identifiable {
    var linkId: String
    var seniorId: String
    var guardianId: String
    var displayName: String?
    var relation: String?
    var linkedAt: Date
    var id: String { linkId }
}

struct ScheduleItem: Codable, Sendable, Identifiable, Hashable {
    var scheduleId: String
    var seniorId: String
    var type: String          // medication (P2)
    var title: String
    var message: String
    var rrule: String         // FREQ=DAILY | FREQ=WEEKLY;BYDAY=MO,WE (backend_spec v0.4 6.4)
    var timeLocal: String     // "08:00"
    var timezone: String      // 어르신 시간대
    var needsAck: Bool
    var reminderAfterMin: Int
    var missedAfterMin: Int
    var active: Bool
    var updatedAt: Date?
    /// G13 시작 날짜 "yyyy-MM-dd"(목 전용 확장, 명세에 없음). 반복 없음(rrule "NONE")이면 이 날 한 번만.
    var startDate: String? = nil
    var id: String { scheduleId }

    var isMedication: Bool { type == "medication" }
}

struct ScheduleAck: Codable, Sendable {
    var dueAt: Date
    var firedAt: Date?
    var ackedAt: Date
    var ackMethod: String      // button | voice | alarm_stop
    var syncedFromOffline: Bool
}

struct Board: Codable, Sendable {
    struct Senior: Codable, Sendable { var displayName: String?; var platform: String? }
    struct TodaySchedule: Codable, Sendable, Identifiable {
        var scheduleId: String; var title: String; var dueAt: Date; var status: String
        var id: String { scheduleId + dueAt.description }
    }
    struct Frequency: Codable, Sendable { var distinctDays7d: Int?; var independentSessions7d: Int? }
    struct AlertItem: Codable, Sendable, Identifiable {
        var alertId: String; var type: String; var riskLevel: RiskLevel?
        var riskDomains: [String]?; var firstDetectedAt: Date?; var lastDetectedAt: Date
        var trend: String?; var frequency: Frequency?
        var recommendedAction: String?     // CHECK_IN | PROMPT_CONTACT | URGENT_SAFETY_CHECK
        var deliveryStatus: String?; var safetyFollowUpStatus: String?
        var id: String { alertId }
    }
    struct Trend: Codable, Sendable, Identifiable { var signal: String; var trend: String; var message: String?; var id: String { signal } }
    struct DeviceStatus: Codable, Sendable {
        var notificationPermission: String; var alarmPermission: String; var lastSeenAt: Date?
    }
    var senior: Senior
    var todaySchedules: [TodaySchedule]       // status: done | not_done | unknown
    var emotion7d: [String: Double]           // POSITIVE / NEUTRAL / NEGATIVE / SURPRISE (명세 v0.6)
    var intensity7d: String?                  // LOW | MODERATE | HIGH
    var baselineStatus: String?               // building | insufficient_activity | ready
    var baselineMessage: String?
    var trends: [Trend]?
    var alertsRecent: [AlertItem]
    var conversationTopics: [String]?         // "이야기 나눈 주제" 최대 3
    var deviceStatus: DeviceStatus?
    /// G04 대화량: 최근 7일 날짜별 대화 수(목 전용 확장, 명세에 없음)
    var conversationCounts7d: [DailyCount]? = nil
    /// G06 관찰된 신호: 영역별 최근 7일 날짜별 관찰 수(목 전용 확장, 명세에 없음)
    var signalCounts7d: [String: [DailyCount]]? = nil
    var updatedAt: Date? = nil

    struct DailyCount: Codable, Sendable, Identifiable, Hashable { var date: String; var count: Int; var id: String { date } }
}

/// 서버 공통 오류 형식 `{ "error": { "code", "message" } }`
struct APIErrorBody: Codable, Sendable {
    struct Inner: Codable, Sendable { var code: String; var message: String }
    var error: Inner
}
