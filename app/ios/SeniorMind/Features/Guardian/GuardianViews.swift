import SwiftUI
import VisionKit

/// 보호자 모드(app_spec 2.2~2.6). 어르신이 Android여도 서버 계약이 같으므로 동일하게 동작.
struct GuardianHomeView: View {
    @Environment(AppState.self) private var app
    @State private var links: [GuardianLink] = []
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                if links.isEmpty {
                    ContentUnavailableView("연결된 어르신이 없어요", systemImage: "person.2",
                                           description: Text("어르신 앱의 '보호자 등록' 화면에 나온 QR 코드를 찍어 주세요."))
                }
                ForEach(links) { link in
                    NavigationLink(value: link.seniorId) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(link.displayName ?? "어르신").font(.headline)
                            Text("\(link.relation ?? "보호자") · \(link.linkedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .navigationTitle("기억의 캡슐")
            .navigationDestination(for: String.self) { BoardView(seniorId: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Label("어르신 연결", systemImage: "qrcode.viewfinder") }
                }
            }
            .task { await reload() }
            .refreshable { await reload() }
            .sheet(isPresented: $showAdd) { LinkSeniorView { Task { await reload() } } }
        }
        .tint(Theme.green)
    }

    private func reload() async { links = (try? await app.api.links()) ?? [] }
}

/// QR 스캔(VisionKit) 또는 6자리 번호 입력 → 연결. QR 형식은 두 OS 공통.
struct LinkSeniorView: View {
    var onLinked: () -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var relation = "자녀"
    @State private var scanning = DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    @State private var error: String?
    @State private var busy = false
    @State private var consentFor: String?

    var body: some View {
        NavigationStack {
            Form {
                if scanning {
                    Section {
                        QRScannerView { text in
                            if let c = DeepLink.parsePairCode(text) { code = c; scanning = false }
                        }
                        .frame(height: 300).listRowInsets(EdgeInsets())
                    } footer: { Text("어르신 화면의 QR 코드를 비춰 주세요.") }
                }
                Section("연결 번호") {
                    TextField("6자리 숫자", text: $code).keyboardType(.numberPad).font(.title2.monospacedDigit())
                    Picker("관계", selection: $relation) {
                        ForEach(["자녀", "배우자", "손자녀", "요양보호사", "기타"], id: \.self) { Text($0) }
                    }
                }
                if let error { Text(error).foregroundStyle(Theme.error) }
                Button(busy ? "연결 중…" : "연결하기") { Task { await link() } }
                    .disabled(code.count != 6 || busy)
            }
            .navigationTitle("어르신 연결")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .onAppear { if let c = DeepLink.pendingPairCode { code = c; DeepLink.pendingPairCode = nil; scanning = false } }
            .sheet(item: Binding(get: { consentFor.map { IdentifiedString(value: $0) } }, set: { consentFor = $0?.value })) { _ in
                // 연결마다 guardian_data_view 동의(app_spec 2.2)
                ConsentFlowView(role: .guardian,
                                steps: [.init(type: .guardianDataView, title: "어르신 정보 열람",
                                              body: "연결한 어르신의 기분 요약, 알림, 일정 확인 기록을 볼 수 있어요. 대화 원문은 볼 수 없어요.", required: true)],
                                linkedSeniorId: nil) {
                    consentFor = nil
                    Task { await link(afterConsent: true) }
                }
            }
        }
    }

    private func link(afterConsent: Bool = false) async {
        busy = true; defer { busy = false }
        do {
            _ = try await app.api.link(code: code, relation: relation)
            onLinked(); dismiss()
        } catch let e as APIError where e.code == "consent_required" && !afterConsent {
            consentFor = code
        } catch let e as APIError {
            error = e.code == "pairing_code_expired" ? "번호가 만료됐어요. 어르신 화면에서 다시 만들어 주세요." : (e.errorDescription ?? "연결하지 못했어요.")
        } catch { self.error = "지금은 연결이 어려워요. 잠시 후 다시 해 주세요." }
    }
}

struct IdentifiedString: Identifiable { let value: String; var id: String { value } }

struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                                           isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in items { if case .barcode(let b) = item, let v = b.payloadStringValue { onCode(v); return } }
        }
    }
}

/// 상태 보드(app_spec 2.5). 원문·점수·감정 7종 이름은 보이지 않는다.
struct BoardView: View {
    let seniorId: String
    @Environment(AppState.self) private var app
    @State private var board: Board?
    @State private var showSchedules = false

    var body: some View {
        List {
            if let b = board {
                if let d = b.deviceStatus, d.alarmPermission != "granted" || d.notificationPermission == "denied" {
                    Label("어르신 휴대폰의 알림·알람이 꺼져 있어요. 어르신 앱 설정에서 켜 주세요.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.error)
                }
                Section("오늘 일정") {
                    if b.todaySchedules.isEmpty { Text("등록된 일정이 없어요.").foregroundStyle(Theme.muted) }
                    ForEach(b.todaySchedules) { s in
                        HStack {
                            Text(s.title).font(.headline)
                            Spacer()
                            Text(s.dueAt.formatted(date: .omitted, time: .shortened)).foregroundStyle(Theme.muted)
                            statusBadge(s.status)
                        }
                    }
                    Button("알림 관리") { showSchedules = true }
                    Text("알림을 확인하셨다는 뜻이며, 실제 복약이나 활동을 확인한 것은 아니에요.").font(.footnote).foregroundStyle(Theme.muted)
                }
                Section("최근 7일 기분") {
                    EmotionBars(values: b.emotion7d)
                    if let i = b.intensity7d {
                        LabeledContent("감정의 세기", value: ["LOW": "낮음", "MODERATE": "보통", "HIGH": "높음"][i] ?? i)
                    }
                    if b.baselineStatus != "ready" {
                        // 명세 v0.6 P10: 기준선 준비 전 "평소 대비" 표시 금지
                        Text(b.baselineMessage ?? "평소 상태를 알아보기 위한 자료를 모으고 있어요.").font(.footnote).foregroundStyle(Theme.muted)
                    } else {
                        ForEach(b.trends ?? []) { t in
                            Text(t.message ?? (t.trend == "insufficient_data" ? "최근 대화 자료가 충분하지 않아 평소와의 변화를 판단하기 어렵습니다." : ""))
                                .font(.subheadline)
                        }
                    }
                }
                Section("이야기 나눈 주제") {
                    let topics = b.conversationTopics ?? []
                    if topics.isEmpty { Text("아직 보여 드릴 주제가 없어요.").foregroundStyle(Theme.muted) }
                    else {
                        HStack { ForEach(topics, id: \.self) { Text($0).padding(.horizontal, 12).padding(.vertical, 6).background(Theme.selectedFill, in: Capsule()) } }
                    }
                }
                Section("최근 알림") {
                    if b.alertsRecent.isEmpty { Text("알림이 없어요.").foregroundStyle(Theme.muted) }
                    ForEach(b.alertsRecent) { a in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(levelText(a.riskLevel)).font(.headline).foregroundStyle(a.riskLevel == .r3 ? Theme.error : Theme.text)
                                Text((a.riskDomains ?? []).map(domainText).joined(separator: " · ")).foregroundStyle(Theme.muted)
                                Spacer()
                                Text(a.lastDetectedAt.formatted(.relative(presentation: .named))).font(.footnote).foregroundStyle(Theme.muted)
                            }
                            if let f = a.frequency, let d = f.distinctDays7d, let s = f.independentSessions7d {
                                Text("최근 7일 \(d)일 · \(s)회 대화에서").font(.footnote).foregroundStyle(Theme.muted)
                            }
                            if let text = ConfigStore.shared.actionText(code: a.recommendedAction) { Text(text).font(.subheadline) }
                            if a.safetyFollowUpStatus == "pending", a.riskLevel == .r3 {
                                Text("안전 확인이 아직 기록되지 않았어요.").font(.footnote).foregroundStyle(Theme.error)
                            }
                        }
                    }
                }
            } else { ProgressView() }
        }
        .navigationTitle(board?.senior.displayName ?? "어르신")
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showSchedules, onDismiss: { Task { await reload() } }) { ScheduleListView(seniorId: seniorId) }
    }

    private func reload() async { board = try? await app.api.board(seniorId: seniorId) }

    /// 명세 v0.6 schedule_status: done / not_done / unknown
    private func statusBadge(_ s: String) -> some View {
        let (text, color): (String, Color) = switch s {
            case "done": ("확인 ✓", Theme.green); case "not_done": ("미확인", Theme.error); default: ("기록 없음", Theme.muted)
        }
        return Text(text).font(.subheadline.bold()).foregroundStyle(color)
    }
    private func levelText(_ l: RiskLevel?) -> String {
        switch l { case .r3: "긴급"; case .r2: "높음"; case .r1: "관심"; default: "알림" }
    }
    /// 명세 v0.6 Guardian_View 표시명
    private func domainText(_ d: String) -> String {
        ["depression": "우울 관련 신호", "anxiety": "불안 관련 신호", "addiction": "중독 관련 우려",
         "self_harm_suicide": "자해·안전 관련 신호", "other_crisis": "급성 혼란·행동 위기"][d] ?? d
    }
}

struct EmotionBars: View {
    let values: [String: Double]
    // 명세 v0.6: POSITIVE / NEUTRAL / NEGATIVE / SURPRISE(독립)
    private let rows: [(String, String, Color)] = [("POSITIVE", "긍정", Color(hex: 0x6C8E60)), ("NEUTRAL", "중립", Color(hex: 0xA9C29C)),
                                                    ("NEGATIVE", "불편", Color(hex: 0x8A9BB0)), ("SURPRISE", "놀람", Color(hex: 0xC59A6B))]
    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows, id: \.0) { row in
                let (key, label, color) = row
                let v = values[key] ?? 0
                HStack {
                    Text(label).frame(width: 70, alignment: .leading)
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 6).fill(Theme.line)
                            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 6).fill(color).frame(width: g.size.width * v) }
                    }.frame(height: 14)
                    Text("\(Int(v * 100))%").font(.footnote.monospacedDigit()).frame(width: 44, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(label) \(Int(v * 100))퍼센트")
            }
        }
        .padding(.vertical, 4)
    }
}

/// 알림 등록·편집(app_spec 2.3). P2는 투약만. 시간은 어르신 시간대 기준.
struct ScheduleListView: View {
    let seniorId: String
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ScheduleItem] = []
    @State private var editing: ScheduleItem?

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    Button { editing = item } label: {
                        VStack(alignment: .leading) {
                            Text(item.title).font(.headline)
                            Text("\(item.timeLocal) · \(repeatText(item.rrule))").font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .onDelete { idx in
                    let ids = idx.map { items[$0].scheduleId }
                    Task { for id in ids { try? await app.api.deleteSchedule(id: id) }; await reload() }
                }
            }
            .navigationTitle("알림 관리")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = .blank(seniorId: seniorId) } label: { Label("추가", systemImage: "plus") }
                }
            }
            .task { await reload() }
            .sheet(item: $editing) { item in ScheduleEditView(item: item) { Task { await reload() } } }
        }
    }
    private func reload() async { items = (try? await app.api.schedules(seniorId: seniorId)) ?? [] }
    private func repeatText(_ rrule: String) -> String {
        if rrule == "FREQ=DAILY" { return "매일" }
        let map = ["MO": "월", "TU": "화", "WE": "수", "TH": "목", "FR": "금", "SA": "토", "SU": "일"]
        return rrule.components(separatedBy: "BYDAY=").last?.split(separator: ",").compactMap { map[String($0)] }.joined(separator: "·") ?? rrule
    }
}

extension ScheduleItem {
    static func blank(seniorId: String) -> ScheduleItem {
        let c = ConfigStore.shared.current.schedule
        return ScheduleItem(scheduleId: "", seniorId: seniorId, type: "medication", title: "", message: "",
                            rrule: "FREQ=DAILY", timeLocal: "08:00", timezone: "Asia/Seoul", needsAck: true,
                            reminderAfterMin: c.reminderAfterMinDefault, missedAfterMin: c.missedAfterMinDefault, active: true, updatedAt: nil)
    }
}

struct ScheduleEditView: View {
    @State var item: ScheduleItem
    var onSaved: () -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()
    @State private var weekdays: Set<Int> = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("이름 (예: 혈압약)", text: $item.title)
                    DatePicker("시간", selection: $time, displayedComponents: .hourAndMinute)
                    Text("어르신 시간대(\(item.timezone)) 기준").font(.footnote).foregroundStyle(Theme.muted)
                }
                Section("반복") {
                    HStack {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in
                            let on = weekdays.contains(d)
                            Button(["", "일", "월", "화", "수", "목", "금", "토"][d]) {
                                if on { weekdays.remove(d) } else { weekdays.insert(d) }
                            }
                            .buttonStyle(.borderless)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(on ? Theme.selectedFill : .clear, in: Circle())
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    Text(weekdays.isEmpty ? "선택하지 않으면 매일" : "선택한 요일마다").font(.footnote).foregroundStyle(Theme.muted)
                }
                Section("알람 문구") {
                    TextField("약 드실 시간이에요", text: $item.message, axis: .vertical)
                    Toggle("확인 받기", isOn: $item.needsAck)
                    Stepper("다시 알림 \(item.reminderAfterMin)분 뒤", value: $item.reminderAfterMin, in: 5...30, step: 5)
                    Stepper("확인 없으면 \(item.missedAfterMin)분 뒤 알림", value: $item.missedAfterMin, in: 30...180, step: 15)
                }
                Section { Text("복약 지도나 용량 안내는 하지 않아요. 알림과 확인만 도와드려요.").font(.footnote).foregroundStyle(Theme.muted) }
                if let error { Text(error).foregroundStyle(Theme.error) }
            }
            .navigationTitle(item.scheduleId.isEmpty ? "투약 알림 추가" : "투약 알림 수정")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("저장") { Task { await save() } }.disabled(item.title.isEmpty) }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        let hm = item.timeLocal.split(separator: ":").compactMap { Int($0) }
        if hm.count == 2 { time = Calendar.current.date(bySettingHour: hm[0], minute: hm[1], second: 0, of: .now) ?? .now }
        if let days = item.rrule.components(separatedBy: "BYDAY=").dropFirst().first {
            weekdays = Set(days.split(separator: ",").compactMap { RRule.weekday(String($0)) })
        }
    }

    private func save() async {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        item.timeLocal = String(format: "%02d:%02d", c.hour ?? 8, c.minute ?? 0)
        item.rrule = RRule.make(weekdays: weekdays)
        if item.message.isEmpty { item.message = "\(item.title) 드실 시간이에요." }
        do { _ = try await app.api.saveSchedule(item); onSaved(); dismiss() }
        catch let e as APIError where e.code == "consent_required" { error = "어르신이 일정 공유에 아직 동의하지 않으셨어요." }
        catch { self.error = "저장하지 못했어요. 잠시 후 다시 해 주세요." }
    }
}
