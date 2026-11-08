import Foundation

/// 백엔드 없이 화면·흐름을 확인하는 목 서버. 판단은 간단한 단어 규칙으로 흉내만 낸다(실제 판단은 서버 gpt-6-luna).
actor MockAPIClient: APIClient {
    private var schedulesStore: [ScheduleItem] = MockAPIClient.seedSchedules()
    private var linksStore: [GuardianLink] = []
    private var alertsStore: [Board.AlertItem] = MockAPIClient.seedAlerts()
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
        let code = String(format: "%06d", Int.random(in: 1...999_999))
        return PairingCode(code: code, expiresAt: .now.addingTimeInterval(300),
                           qrPayload: "memorycapsule://pair?v=1&code=\(code)")
    }
    /// 목 규칙: 6자리면 성공, "000000"은 만료(G26 화면 확인용).
    func resolvePairing(code: String) async throws -> PairingTarget {
        try check(code)
        return PairingTarget(seniorId: seniorId, displayName: "김영희", expiresAt: .now.addingTimeInterval(240))
    }
    func link(code: String, relation: String) async throws -> GuardianLink {
        try check(code)
        if linksStore.contains(where: { $0.seniorId == seniorId }) {
            throw APIError.server(status: 409, code: "already_linked", message: "이미 연결된 부모님이에요.")
        }
        let link = GuardianLink(linkId: UUID().uuidString, seniorId: seniorId, guardianId: "mock-guardian",
                                displayName: "김영희", relation: relation, linkedAt: .now)
        linksStore.append(link); return link
    }
    private func check(_ code: String) throws {
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw APIError.server(status: 400, code: "pairing_code_invalid", message: "번호가 맞지 않거나 만료됐어요.")
        }
        if code == "000000" { throw APIError.server(status: 400, code: "pairing_code_expired", message: "번호가 맞지 않거나 만료됐어요.") }
    }
    func links() async throws -> [GuardianLink] { linksStore }
    func unlink(linkId: String) async throws { linksStore.removeAll { $0.linkId == linkId } }

    func board(seniorId: String) async throws -> Board {
        let today = todaySchedules()
        let days = (0..<7).reversed().map { Calendar.current.date(byAdding: .day, value: -$0, to: .now)! }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let talks = [2, 3, 1, 2, 0, 3, 2]
        let depression = [0, 0, 1, 0, 0, 1, 2]
        return Board(senior: .init(displayName: "김영희", platform: "ios"),
                     todaySchedules: today,
                     emotion7d: ["POSITIVE": 0.40, "NEUTRAL": 0.30, "NEGATIVE": 0.20, "SURPRISE": 0.10],
                     intensity7d: "MODERATE", baselineStatus: "ready", baselineMessage: nil,
                     trends: [.init(signal: "NEGATIVE", trend: "increasing", message: "최근 2주간 불편한 표현이 평소보다 자주 나타났어요.")],
                     alertsRecent: Array(alertsStore.prefix(3)),
                     conversationTopics: ["산책", "손녀", "정원 가꾸기"],
                     deviceStatus: .init(notificationPermission: "granted", alarmPermission: "granted", lastSeenAt: .now),
                     conversationCounts7d: zip(days, talks).map { .init(date: fmt.string(from: $0), count: $1) },
                     signalCounts7d: ["depression": zip(days, depression).map { .init(date: fmt.string(from: $0), count: $1) },
                                      "anxiety": days.map { .init(date: fmt.string(from: $0), count: 0) }],
                     updatedAt: .now.addingTimeInterval(-600))
    }

    func alerts(seniorId: String) async throws -> [Board.AlertItem] { alertsStore }
    func markAlertRead(id: String) async throws {
        if let i = alertsStore.firstIndex(where: { $0.alertId == id }), alertsStore[i].deliveryStatus != "safety_checked" {
            alertsStore[i].deliveryStatus = "read"
        }
    }
    func alertFollowUp(id: String, status: String) async throws {
        if let i = alertsStore.firstIndex(where: { $0.alertId == id }) {
            alertsStore[i].safetyFollowUpStatus = status; alertsStore[i].deliveryStatus = "safety_checked"
        }
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

    // MARK: - 목 데이터

    private func todaySchedules() -> [Board.TodaySchedule] {
        let start = Calendar.current.startOfDay(for: .now)
        return schedulesStore.filter(\.active).flatMap { s in
            RRule.occurrences(s, from: start, to: start.addingTimeInterval(86_399)).map { due in
                let key = "\(s.scheduleId)|\(Int(due.timeIntervalSince1970))"
                let status = !s.needsAck ? "unknown" : acks[key] != nil ? "done" : (due < .now ? "not_done" : "unknown")
                return Board.TodaySchedule(scheduleId: s.scheduleId, title: s.title, dueAt: due, status: status)
            }
        }
        .sorted { $0.dueAt < $1.dueAt }
    }

    private static func seedSchedules() -> [ScheduleItem] {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: .now)
        return [
            ScheduleItem(scheduleId: "s1", seniorId: "mock-senior", type: "medication", title: "혈압약", message: "혈압약 드실 시간이에요",
                         rrule: "FREQ=DAILY", timeLocal: "08:30", timezone: "Asia/Seoul", needsAck: true,
                         reminderAfterMin: 10, missedAfterMin: 60, active: true, updatedAt: .now, startDate: today),
            ScheduleItem(scheduleId: "s2", seniorId: "mock-senior", type: "other", title: "병원 방문", message: "병원 가실 시간이에요",
                         rrule: "NONE", timeLocal: "14:00", timezone: "Asia/Seoul", needsAck: true,
                         reminderAfterMin: 10, missedAfterMin: 60, active: true, updatedAt: .now, startDate: today),
        ]
    }

    private static func seedAlerts() -> [Board.AlertItem] {
        [
            .init(alertId: "a1", type: "risk", riskLevel: .r2, riskDomains: ["depression"],
                  firstDetectedAt: .now.addingTimeInterval(-3600 * 40), lastDetectedAt: .now.addingTimeInterval(-3600 * 3),
                  trend: "increasing", frequency: .init(distinctDays7d: 2, independentSessions7d: 3),
                  recommendedAction: "PROMPT_CONTACT", deliveryStatus: "delivered", safetyFollowUpStatus: "pending"),
            .init(alertId: "a2", type: "schedule_missed", riskLevel: nil, riskDomains: nil,
                  firstDetectedAt: .now.addingTimeInterval(-3600 * 26), lastDetectedAt: .now.addingTimeInterval(-3600 * 26),
                  trend: nil, frequency: nil, recommendedAction: nil, deliveryStatus: "read", safetyFollowUpStatus: nil),
        ]
    }
}
