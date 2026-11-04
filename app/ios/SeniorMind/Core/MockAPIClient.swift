import Foundation

/// 백엔드 없이 화면·흐름을 확인하는 목 서버. 판단은 간단한 단어 규칙으로 흉내만 낸다(실제 판단은 서버 gpt-6-luna).
actor MockAPIClient: APIClient {
    private var schedulesStore: [ScheduleItem] = []
    private var linksStore: [GuardianLink] = []
    private var acks: [String: Date] = [:]
    private let seniorId = "mock-senior"

    func upsertMe(_ body: UserUpsert) async throws -> UserProfile {
        UserProfile(userId: body.role == .senior ? seniorId : "mock-guardian", role: body.role, displayName: body.displayName, timezone: body.timezone)
    }
    func registerDevice(_ body: DeviceRegister) async throws {}
    func postConsent(_ body: ConsentRequest) async throws {}
    func config() async throws -> ConfigResponse {
        ConfigResponse(configVersion: AppConfig.builtIn.configVersion, config: .builtIn, signature: nil)
    }

    func createSession(_ body: SessionCreateRequest) async throws -> SessionCreateResponse {
        .init(session: .init(id: "mock-session-\(Int(Date().timeIntervalSince1970))", maxSeconds: 180),
              transport: .init(type: "webrtc", sdp: ""))
    }

    func decision(_ body: DecisionRequest) async throws -> DecisionResponse {
        try await Task.sleep(for: .milliseconds(Int.random(in: 180...420)))
        let t = body.inputText.suffix(120)
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        var risk: RiskLevel = .r0
        var reaction: Reaction = .neutral
        var phraseId: String? = nil
        if has(["죽고 싶", "사라지고 싶", "살기 싫"]) && !has(["싶진 않", "싶지 않"]) { risk = .r3; reaction = .empathy; phraseId = "R3_SUICIDE_SUPPORT" }
        else if has(["불안해서 미치", "숨이 막", "가슴이 두근"]) { risk = .r2; reaction = .empathy; phraseId = "SAFE_ANXIETY" }
        else if has(["아무것도 재미없", "다 소용없", "쓸모없"]) { risk = .r2; reaction = .empathy; phraseId = "R2_CHECK_IN" }
        else if has(["다쳤", "넘어졌", "화상", "넘어져"]) && !has(["안 다쳤", "괜찮아"]) { reaction = .surprisedConcern }
        else if has(["또 온대", "온대요", "합격", "선물"]) { reaction = .surprisedHappy }
        else if has(["쓸쓸", "외로", "힘들", "아파"]) { reaction = .empathy; risk = has(["외로"]) ? .r1 : .r0 }
        else if has(["좋았", "좋아", "기뻐", "반가"]) { reaction = .happy }
        else if t.hasSuffix("…") || t.count < 6 { reaction = .hold }
        var control: MemoryControl = .none
        if has(["지워줘", "잊어줘"]) { control = .delete }
        else if has(["보여주지 마", "말하지 마"]) { control = .doNotShare }
        return DecisionResponse(reaction: reaction, riskLevel: risk, assessmentStatus: "assessed",
                                safetyOverride: phraseId != nil, safetyPhraseId: phraseId,
                                memoryControl: control, assessmentId: UUID().uuidString,
                                usage: .init(inputTokens: 300 + body.inputText.count), latencyMs: nil)
    }
    func endSession(id: String, _ body: SessionEndRequest) async throws {}
    func memoryControl(_ body: MemoryControlRequest) async throws {}

    func pairingCode() async throws -> PairingCode {
        let code = String(format: "%06d", Int.random(in: 0...999_999))
        return PairingCode(code: code, expiresAt: .now.addingTimeInterval(300),
                           qrPayload: "seniormind://pair?v=1&code=\(code)")
    }
    func link(code: String, relation: String) async throws -> GuardianLink {
        guard code.count == 6 else { throw APIError.server(status: 400, code: "pairing_code_invalid", message: "코드를 다시 확인해 주세요.") }
        let link = GuardianLink(linkId: UUID().uuidString, seniorId: seniorId, guardianId: "mock-guardian",
                                displayName: "영희 어르신", relation: relation, linkedAt: .now)
        linksStore.append(link); return link
    }
    func links() async throws -> [GuardianLink] { linksStore }
    func unlink(linkId: String) async throws { linksStore.removeAll { $0.linkId == linkId } }

    func board(seniorId: String) async throws -> Board {
        let cal = Calendar.current
        let today = schedulesStore.filter(\.active).compactMap { s -> Board.TodaySchedule? in
            let parts = s.timeLocal.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, let due = cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: .now) else { return nil }
            let key = "\(s.scheduleId)|\(Int(due.timeIntervalSince1970))"
            let status = acks[key] != nil ? "done" : "not_done"
            return .init(scheduleId: s.scheduleId, title: s.title, dueAt: due, status: status)
        }
        return Board(senior: .init(displayName: "영희 어르신", platform: "ios"),
                     todaySchedules: today,
                     emotion7d: ["POSITIVE": 0.42, "NEUTRAL": 0.33, "NEGATIVE": 0.17, "SURPRISE": 0.08],
                     intensity7d: "MODERATE", baselineStatus: "building",
                     baselineMessage: "평소 상태를 알아보기 위한 자료를 모으고 있어요. 아직 평소와의 변화를 판단하기에는 정보가 충분하지 않습니다.",
                     trends: [],
                     alertsRecent: [.init(alertId: "a1", type: "risk", riskLevel: .r2, riskDomains: ["depression"],
                                          firstDetectedAt: .now.addingTimeInterval(-3600 * 40), lastDetectedAt: .now.addingTimeInterval(-3600 * 20),
                                          trend: "insufficient_data", frequency: .init(distinctDays7d: 2, independentSessions7d: 3),
                                          recommendedAction: "PROMPT_CONTACT", deliveryStatus: "read", safetyFollowUpStatus: "pending")],
                     conversationTopics: ["산책", "손녀", "정원 가꾸기"],
                     deviceStatus: .init(notificationPermission: "granted", alarmPermission: "granted", lastSeenAt: .now))
    }

    func schedules(seniorId: String) async throws -> [ScheduleItem] { schedulesStore.filter(\.active) }
    func saveSchedule(_ item: ScheduleItem) async throws -> ScheduleItem {
        var item = item
        if item.scheduleId.isEmpty { item.scheduleId = UUID().uuidString }
        item.updatedAt = .now
        schedulesStore.removeAll { $0.scheduleId == item.scheduleId }
        schedulesStore.append(item)
        return item
    }
    func deleteSchedule(id: String) async throws { schedulesStore.removeAll { $0.scheduleId == id } }
    func ack(scheduleId: String, _ body: ScheduleAck) async throws {
        acks["\(scheduleId)|\(Int(body.dueAt.timeIntervalSince1970))"] = body.ackedAt
    }
}
