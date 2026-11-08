import SwiftUI
import Charts

/// 보호자 모드 전체. 단계에 따라 로그인·이름·동의·연결·탭 화면을 보여 준다.
struct GuardianRootView: View {
    @Environment(AppState.self) private var app
    @State private var store = GuardianStore(auth: AppState.shared.auth)

    var body: some View {
        Group {
            switch store.stage {
            case .auth: GuardianLoginView()
            case .profile: GuardianProfileView()
            case .consent:
                // 보호자 약관·일정 관리 동의. guardian_data_view는 부모님을 확인한 뒤 G24에서 받는다.
                ConsentFlowView(role: .guardian, steps: ConsentStep.guardian) { store.consentDone = true }
            case .loadingLinks:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
                    .task { await store.loadLinks(app.api) }
            case .linksError:
                GuardianErrorView { Task { await store.loadLinks(app.api) } }
                    .frame(maxHeight: .infinity).background(Theme.background)
            case .link: GuardianLinkFlow()
            case .main: GuardianMainView()
            }
        }
        .environment(store)
        .animation(.easeInOut(duration: 0.2), value: store.stage)
    }
}

/// 탭: 오늘(G04) / 알림(G07) / 약·일정(G12) / 설정(G16). 전화하기 버튼은 두지 않는다.
struct GuardianMainView: View {
    @Environment(AppState.self) private var app
    @Environment(GuardianStore.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.tab) {
            Tab("오늘", systemImage: "house.fill", value: GuardianTab.today) {
                NavigationStack { GuardianTodayView() }
            }
            Tab("알림", systemImage: "bell.fill", value: GuardianTab.alerts) {
                NavigationStack { GuardianAlertsView() }
            }
            .badge(store.unreadAlerts)
            Tab("약·일정", systemImage: "pills.fill", value: GuardianTab.schedules) {
                NavigationStack { GuardianScheduleListView() }
            }
            Tab("설정", systemImage: "gearshape.fill", value: GuardianTab.settings) {
                NavigationStack { GuardianSettingsView() }
            }
        }
        .tint(Theme.green)
        .task { await store.loadBoard(app.api) }
    }
}

/// G04 · 부모님의 오늘 (G10 빈 화면, G11 오류)
struct GuardianTodayView: View {
    @Environment(AppState.self) private var app
    @Environment(GuardianStore.self) private var store

    var body: some View {
        GuardianScaffold(title: "\(store.seniorName)님의 오늘") {
            switch store.boardState {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 240)
            case .failed where store.board == nil:
                GuardianErrorView { Task { await store.loadBoard(app.api) } }
            default:
                if let b = store.board {
                    if b.isEmpty { GuardianEmptyView() } else { content(b) }
                }
            }
        }
        .refreshable { await store.loadBoard(app.api) }
    }

    @ViewBuilder private func content(_ b: Board) -> some View {
        if let t = b.updatedAt {
            Text("\(t.formatted(date: .abbreviated, time: .shortened)) 기준").font(.system(size: 15)).foregroundStyle(Theme.muted)
        }
        if let d = b.deviceStatus, d.alarmPermission != "granted" || d.notificationPermission == "denied" {
            GuardianErrorText(text: "부모님 휴대폰의 알림·알람이 꺼져 있어요. 부모님 앱 설정에서 켜 주세요.")
        }
        if store.unreadAlerts > 0 {
            Button { store.tab = .alerts } label: {
                GuardianRowLabel(title: "확인이 필요한 신호가 있어요", detail: "새 알림 \(store.unreadAlerts)개", tint: Theme.error)
            }
            .buttonStyle(.plain)
        }
        summary(b)
        GuardianCard(title: "대화량", trailing: AnyView(Text("최근 7일").font(.system(size: 15)).foregroundStyle(Theme.muted))) {
            let counts = b.conversationCounts7d ?? []
            if counts.isEmpty {
                Text("대화량은 서버 준비 후 보여 드려요.").font(.system(size: 16)).foregroundStyle(Theme.muted)
            } else {
                DailyBars(counts: counts, unit: "번")
                Text("오늘 \(counts.last?.count ?? 0)번 이야기했어요").font(.system(size: 17, weight: .semibold))
            }
        }
        GuardianCard(title: "감정 변화", trailing: AnyView(
            NavigationLink { GuardianEmotionView(board: b) } label: { Text("자세히 ›").font(.system(size: 16, weight: .semibold)) }
        )) {
            if let top = EmotionSlice.from(b.emotion7d).max(by: { $0.value < $1.value }) {
                Text("최근 7일은 \(top.label) 표현이 가장 많았어요.").font(.system(size: 17))
            } else {
                Text("아직 보여 드릴 감정 기록이 없어요.").font(.system(size: 16)).foregroundStyle(Theme.muted)
            }
        }
        GuardianCard(title: "약·일정 확인", trailing: AnyView(
            NavigationLink { GuardianDailyCheckView() } label: { Text("자세히 ›").font(.system(size: 16, weight: .semibold)) }
        )) {
            let parts = split(b.todaySchedules)
            HStack(spacing: 12) {
                countBox("오늘 약", parts.med)
                countBox("일정", parts.other)
            }
        }
    }

    private func summary(_ b: Board) -> some View {
        GuardianCard(title: "요약") {
            let topics = b.conversationTopics ?? []
            if !topics.isEmpty {
                HStack(spacing: 8) { ForEach(topics.prefix(3), id: \.self) { GuardianTag(text: $0) } }
            }
            Text(summaryMessage(b)).font(.system(size: 18)).lineSpacing(3)
        }
    }

    private func summaryMessage(_ b: Board) -> String {
        if b.baselineStatus != "ready" {
            // 명세 v0.6 P10: 기준선 준비 전 "평소 대비" 표시 금지
            return b.baselineMessage ?? "평소 상태를 알아보기 위한 자료를 모으고 있어요."
        }
        return b.trends?.compactMap(\.message).first ?? "최근 큰 변화 없이 지내고 계세요."
    }

    private func split(_ list: [Board.TodaySchedule]) -> (med: [Board.TodaySchedule], other: [Board.TodaySchedule]) {
        let medIds = Set(store.schedules.filter(\.isMedication).map(\.scheduleId))
        return (list.filter { medIds.contains($0.scheduleId) }, list.filter { !medIds.contains($0.scheduleId) })
    }

    private func countBox(_ title: String, _ items: [Board.TodaySchedule]) -> some View {
        let done = items.filter { $0.status == "done" }.count
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 15)).foregroundStyle(Theme.muted)
            Text("\(done)/\(items.count)").font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.green)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.secondaryFill, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(items.count)개 중 \(done)개 확인")
    }
}

/// 날짜별 막대(대화량·관찰된 신호)
struct DailyBars: View {
    let counts: [Board.DailyCount]
    var unit: String = "회"
    var color: Color = Theme.selectedBorder

    var body: some View {
        Chart(counts) { c in
            BarMark(x: .value("날짜", GuardianText.dayLabel(c.date)), y: .value("횟수", c.count), width: .ratio(0.55))
                .foregroundStyle(color)
                .cornerRadius(4)
                .accessibilityLabel(Text(GuardianText.dayLabel(c.date)))
                .accessibilityValue(Text("\(c.count)\(unit)"))
        }
        .chartYAxis(.hidden)
        .frame(height: 120)
    }
}

struct EmotionSlice: Identifiable {
    let key: String, label: String, color: Color, value: Double
    var id: String { key }
    /// 명세 v0.6: POSITIVE / NEUTRAL / NEGATIVE / SURPRISE(독립)
    static func from(_ values: [String: Double]) -> [EmotionSlice] {
        [("POSITIVE", "긍정", Color(hex: 0x6C8E60)), ("NEUTRAL", "중립", Color(hex: 0xA9C29C)),
         ("NEGATIVE", "불편", Color(hex: 0x8A9BB0)), ("SURPRISE", "놀람", Color(hex: 0xC59A6B))]
            .compactMap { t in values[t.0].map { EmotionSlice(key: t.0, label: t.1, color: t.2, value: $0) } }
    }
}

/// G06 · 감정 변화 자세히
struct GuardianEmotionView: View {
    let board: Board
    @State private var domain: String

    init(board: Board) {
        self.board = board
        _domain = State(initialValue: board.signalCounts7d?.keys.sorted().first ?? "")
    }

    var body: some View {
        let slices = EmotionSlice.from(board.emotion7d)
        GuardianScaffold(title: "감정 변화") {
            GuardianCard(title: "최근 7일 감정 표현") {
                if slices.isEmpty {
                    Text("아직 보여 드릴 감정 기록이 없어요.").foregroundStyle(Theme.muted)
                } else {
                    HStack(spacing: 18) {
                        Chart(slices) { s in
                            SectorMark(angle: .value("비율", s.value), innerRadius: .ratio(0.55), angularInset: 1.5)
                                .foregroundStyle(s.color)
                        }
                        .frame(width: 130, height: 130)
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(slices) { s in
                                HStack(spacing: 8) {
                                    Circle().fill(s.color).frame(width: 12, height: 12)
                                    Text(s.label).font(.system(size: 17))
                                    Spacer()
                                    Text("\(Int((s.value * 100).rounded()))%").font(.system(size: 17, weight: .semibold).monospacedDigit())
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(s.label) \(Int((s.value * 100).rounded()))퍼센트")
                            }
                        }
                    }
                }
                if let i = board.intensity7d {
                    HStack { Text("표현 강도").foregroundStyle(Theme.muted); Spacer(); Text(GuardianText.intensity(i)).bold() }
                        .font(.system(size: 17)).padding(.top, 4)
                }
            }
            GuardianCard(title: "평소와 비교") {
                if board.baselineStatus == "ready" {
                    let msgs = (board.trends ?? []).compactMap(\.message)
                    Text(msgs.first ?? "평소와 비슷하게 지내고 계세요.").font(.system(size: 17)).lineSpacing(3)
                } else {
                    Text(board.baselineMessage ?? "평소 상태를 알아보기 위한 자료를 모으고 있어요.")
                        .font(.system(size: 17)).foregroundStyle(Theme.muted)
                }
            }
            GuardianCard(title: "관찰된 신호") {
                let keys = board.signalCounts7d?.keys.sorted() ?? []
                if keys.isEmpty {
                    Text("관찰된 신호는 서버 준비 후 보여 드려요.").font(.system(size: 16)).foregroundStyle(Theme.muted)
                } else {
                    Picker("신호", selection: $domain) {
                        ForEach(keys, id: \.self) { Text(GuardianText.domain($0)).tag($0) }
                    }
                    .pickerStyle(.menu)
                    DailyBars(counts: board.signalCounts7d?[domain] ?? [], unit: "번", color: Color(hex: 0x8A9BB0))
                }
                Text("신호는 진단이 아니에요. 평소와 다른 변화를 살펴보는 참고 자료예요.")
                    .font(.system(size: 15)).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// G07 · 신호 알림 목록
struct GuardianAlertsView: View {
    @Environment(AppState.self) private var app
    @Environment(GuardianStore.self) private var store

    var body: some View {
        GuardianScaffold(title: "신호 알림") {
            if store.alerts.isEmpty {
                Text("새로운 신호 알림이 없어요.").font(.system(size: 18)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
            ForEach(store.alerts) { a in
                NavigationLink { GuardianAlertDetailView(alertId: a.alertId) } label: { row(a) }
                    .buttonStyle(.plain)
            }
        }
        .task { await store.loadAlerts(app.api) }
        .refreshable { await store.loadAlerts(app.api) }
    }

    private func row(_ a: Board.AlertItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(GuardianStore.isRead(a) ? Color.clear : Theme.error).frame(width: 10, height: 10).padding(.top, 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(AlertText.title(a)).font(.system(size: 18, weight: .bold))
                    .foregroundStyle(a.riskLevel == .r3 ? Theme.error : Theme.text)
                Text(a.lastDetectedAt.formatted(.relative(presentation: .named))).font(.system(size: 15)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text("›").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.cardBorder))
        .accessibilityElement(children: .combine)
        .accessibilityHint(GuardianStore.isRead(a) ? "" : "읽지 않은 알림")
    }
}

enum AlertText {
    static func title(_ a: Board.AlertItem) -> String {
        if a.type == "schedule_missed" { return "약·일정 확인이 늦어지고 있어요" }
        let domains = (a.riskDomains ?? []).map(GuardianText.domain).joined(separator: " · ")
        return "[\(GuardianText.level(a.riskLevel))] " + (domains.isEmpty ? "확인이 필요한 신호" : domains)
    }
    static func action(_ a: Board.AlertItem) -> String {
        if let t = ConfigStore.shared.actionText(code: a.recommendedAction) { return t }
        switch a.recommendedAction {
        case "URGENT_SAFETY_CHECK": return "지금 바로 부모님의 안전을 확인해 주세요."
        case "PROMPT_CONTACT": return "오늘 중에 부모님께 안부 연락을 해 보세요."
        case "CHECK_IN": return "다음 연락 때 요즘 지내시는 이야기를 들어 보세요."
        default: return a.type == "schedule_missed" ? "부모님이 알림을 확인하셨는지 살펴봐 주세요." : "부모님의 안부를 살펴봐 주세요."
        }
    }
}

/// G07 · 신호 알림 자세히. 열면 읽음 처리. 긴급(R3)은 안전 확인 기록을 남긴다.
struct GuardianAlertDetailView: View {
    let alertId: String
    @Environment(AppState.self) private var app
    @Environment(GuardianStore.self) private var store
    @State private var error: String?

    var body: some View {
        GuardianScaffold(title: "신호 알림") {
            if let a = store.alerts.first(where: { $0.alertId == alertId }) {
                GuardianCard {
                    Text(AlertText.title(a)).font(.system(size: 21, weight: .bold))
                        .foregroundStyle(a.riskLevel == .r3 ? Theme.error : Theme.text)
                    if let first = a.firstDetectedAt {
                        info("처음 관찰", first.formatted(date: .abbreviated, time: .shortened))
                    }
                    info("최근 관찰", a.lastDetectedAt.formatted(date: .abbreviated, time: .shortened))
                    if let f = a.frequency, let d = f.distinctDays7d, let s = f.independentSessions7d {
                        info("최근 7일", "\(d)일 · 대화 \(s)회에서")
                    }
                    if let t = GuardianText.trend(a.trend) { info("변화", t) }
                }
                GuardianCard(title: "이렇게 해 보세요") {
                    Text(AlertText.action(a)).font(.system(size: 18)).lineSpacing(3)
                    if a.riskLevel == .r3 {
                        let h = ConfigStore.shared.current.safety.hotline
                        Text("위급하면 \(h.name) \(h.number) 또는 119에 도움을 요청하세요.")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.error)
                    }
                }
                Text("AI가 알려 드리는 참고 정보예요. 판단과 연락은 보호자님이 정해요.")
                    .font(.system(size: 15)).foregroundStyle(Theme.muted)
                if let error { GuardianErrorText(text: error) }
            }
        } bottom: {
            if let a = store.alerts.first(where: { $0.alertId == alertId }), a.type == "risk" {
                if a.safetyFollowUpStatus == "pending" || a.safetyFollowUpStatus == nil {
                    Button("부모님 안부를 확인했어요") { Task { await followUp(a) } }.buttonStyle(PrimaryButtonStyle())
                } else {
                    Text("안부 확인을 기록했어요 ✓").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.green)
                        .frame(minHeight: 56)
                }
            }
        }
        .task {
            if let a = store.alerts.first(where: { $0.alertId == alertId }) { await store.markRead(a, api: app.api) }
        }
    }

    private func info(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundStyle(Theme.muted).frame(width: 80, alignment: .leading)
            Text(v)
        }
        .font(.system(size: 17))
    }

    private func followUp(_ a: Board.AlertItem) async {
        do { try await store.followUp(a, status: "verified", api: app.api) }
        catch { self.error = "기록하지 못했어요. 잠시 후 다시 해 주세요." }
    }
}

/// G33 · 약·일정 확인(오늘)
struct GuardianDailyCheckView: View {
    @Environment(GuardianStore.self) private var store

    var body: some View {
        let today = store.board?.todaySchedules ?? []
        GuardianScaffold(title: "약·일정 확인") {
            Text(Date.now.formatted(date: .complete, time: .omitted)).font(.system(size: 17, weight: .semibold))
            if today.isEmpty { Text("오늘 등록된 약·일정이 없어요.").foregroundStyle(Theme.muted) }
            ForEach(today) { s in
                let item = store.schedules.first { $0.scheduleId == s.scheduleId }
                let status = GuardianText.status(s.status)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.title).font(.system(size: 19, weight: .bold))
                        Text("\(item.map(GuardianText.kind) ?? "일정") · \(s.dueAt.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 15)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(status.0).font(.system(size: 16, weight: .bold)).foregroundStyle(status.1)
                }
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder))
                .accessibilityElement(children: .combine)
            }
            Text("알림을 확인하셨다는 뜻이며, 실제 복약이나 활동을 확인한 것은 아니에요.")
                .font(.system(size: 15)).foregroundStyle(Theme.muted)
        }
    }
}
