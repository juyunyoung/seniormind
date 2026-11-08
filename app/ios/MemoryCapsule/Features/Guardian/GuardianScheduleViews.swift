import SwiftUI

/// G12 · 약·일정 목록
struct GuardianScheduleListView: View {
    @Environment(AppState.self) private var app
    @Environment(GuardianStore.self) private var store

    var body: some View {
        GuardianScaffold(title: "약·일정") {
            if store.schedules.isEmpty {
                Text("등록된 약·일정이 없어요.\n부모님께 알려 드릴 약이나 일정을 추가해 보세요.")
                    .font(.system(size: 17)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, minHeight: 160)
                    .multilineTextAlignment(.center)
            }
            ForEach(store.schedules) { item in
                NavigationLink(value: item) { row(item) }.buttonStyle(.plain)
            }
        } bottom: {
            NavigationLink(value: ScheduleItem.blank(seniorId: store.current?.seniorId ?? "")) {
                Text("약·일정 추가하기")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .navigationDestination(for: ScheduleItem.self) { GuardianScheduleEditView(item: $0) }
        .task { await store.loadSchedules(app.api) }
        .refreshable { await store.loadSchedules(app.api) }
    }

    private func row(_ item: ScheduleItem) -> some View {
        let start = GuardianText.date(item.startDate)?.formatted(date: .abbreviated, time: .omitted)
        return GuardianRowLabel(title: item.title,
                                detail: "\(GuardianText.kind(item))\(start.map { " · \($0)" } ?? "")\n\(item.timeLocal) · \(GuardianText.repeatText(item.rrule))")
    }
}

/// G13 · 약·일정 추가·수정 (G15 삭제 확인)
struct GuardianScheduleEditView: View {
    @State var item: ScheduleItem
    @Environment(AppState.self) private var app
    @Environment(GuardianStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var time = Date()
    @State private var confirmDelete = false
    @State private var error: String?
    @State private var busy = false

    private var isNew: Bool { item.scheduleId.isEmpty }

    var body: some View {
        GuardianScaffold(title: isNew ? "약·일정 추가" : "약·일정 수정") {
            VStack(alignment: .leading, spacing: 8) {
                Text("종류").font(.system(size: 17, weight: .bold))
                Picker("종류", selection: $item.type) {
                    Text("약").tag("medication")
                    Text("일정").tag("other")
                }
                .pickerStyle(.segmented)
            }
            GuardianField("이름", text: $item.title, placeholder: item.isMedication ? "예: 혈압약" : "예: 병원 방문")
            GuardianCard {
                DatePicker("시작 날짜", selection: $start, displayedComponents: .date)
                Divider()
                DatePicker("알림 시간", selection: $time, displayedComponents: .hourAndMinute)
            }
            .font(.system(size: 18, weight: .semibold))
            NavigationLink { GuardianRepeatView(rrule: $item.rrule) } label: {
                GuardianRowLabel(title: "반복 설정", detail: GuardianText.repeatText(item.rrule))
            }
            .buttonStyle(.plain)
            Text("부모님 휴대폰 시간(\(item.timezone)) 기준으로 알려 드려요. 복약 지도나 용량 안내는 하지 않아요.")
                .font(.system(size: 15)).foregroundStyle(Theme.muted)
            if let error { GuardianErrorText(text: error) }
        } bottom: {
            Button(busy ? "저장 중…" : "저장하기") { Task { await save() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(item.title.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            if !isNew {
                Button("이 항목 삭제하기", role: .destructive) { confirmDelete = true }
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.error).frame(minHeight: 44)
            }
        }
        .alert("이 항목을 지울까요?", isPresented: $confirmDelete) {   // G15
            Button("취소", role: .cancel) {}
            Button("지우기", role: .destructive) { Task { await delete() } }
        } message: {
            Text("앞으로의 안내와 알림을 지워요. 이미 확인한 내역은 유지해요.")
        }
        .onAppear(perform: load)
    }

    private func load() {
        let hm = item.timeLocal.split(separator: ":").compactMap { Int($0) }
        if hm.count == 2 { time = Calendar.current.date(bySettingHour: hm[0], minute: hm[1], second: 0, of: .now) ?? .now }
        start = GuardianText.date(item.startDate) ?? .now
    }

    private func save() async {
        busy = true; error = nil; defer { busy = false }
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        item.title = item.title.trimmingCharacters(in: .whitespaces)
        item.timeLocal = String(format: "%02d:%02d", c.hour ?? 8, c.minute ?? 0)
        item.startDate = GuardianText.dateString(start)
        item.message = item.isMedication ? "\(item.title) 드실 시간이에요." : "\(item.title) 시간이에요."
        do { try await store.save(item, api: app.api); dismiss() }
        catch let e as APIError where e.code == "consent_required" { error = "부모님이 일정 공유에 아직 동의하지 않으셨어요." }
        catch { self.error = "저장하지 못했어요. 잠시 후 다시 해 주세요." }
    }

    private func delete() async {
        do { try await store.delete(item, api: app.api); dismiss() }
        catch { self.error = "지우지 못했어요. 잠시 후 다시 해 주세요." }
    }
}

/// G27 · 반복 알림 설정
struct GuardianRepeatView: View {
    @Binding var rrule: String
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .daily
    @State private var weekdays: Set<Int> = []
    enum Mode { case none, daily, weekly }

    var body: some View {
        GuardianScaffold(title: "반복 알림 설정") {
            Text("반복 주기").font(.system(size: 17, weight: .bold))
            GuardianOptionRow(title: "반복 없음", selected: mode == .none) { mode = .none }
            GuardianOptionRow(title: "매일", selected: mode == .daily) { mode = .daily }
            GuardianOptionRow(title: "요일 선택", selected: mode == .weekly) { mode = .weekly }
            if mode == .weekly {
                HStack(spacing: 6) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in
                        let on = weekdays.contains(d)
                        Button(["", "일", "월", "화", "수", "목", "금", "토"][d]) {
                            if on { weekdays.remove(d) } else { weekdays.insert(d) }
                        }
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(on ? Color.white : Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? Theme.green : Color.white, in: Circle())
                        .overlay(Circle().stroke(Theme.cardBorder))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            Text(footer).font(.system(size: 16)).foregroundStyle(Theme.muted)
        } bottom: {
            Button("반복 설정 완료") { apply(); dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(mode == .weekly && weekdays.isEmpty)
        }
        .onAppear(perform: load)
    }

    private var footer: String {
        switch mode {
        case .none: "선택한 날짜와 시간에 한 번 알려드려요."
        case .daily: "시작 날짜부터 매일 같은 시간에 알려드려요."
        case .weekly: "시작 날짜부터 선택한 요일마다 알려드려요."
        }
    }

    private func load() {
        if rrule == "NONE" { mode = .none }
        else if let days = rrule.components(separatedBy: "BYDAY=").dropFirst().first {
            weekdays = Set(days.split(separator: ",").compactMap { RRule.weekday(String($0)) })
            mode = .weekly
        } else { mode = .daily }
    }

    /// 반복 없음은 "NONE"(목 전용 확장, 팀 서버 명세는 FREQ=DAILY | WEEKLY만)
    private func apply() {
        switch mode {
        case .none: rrule = "NONE"
        case .daily: rrule = "FREQ=DAILY"
        case .weekly: rrule = RRule.make(weekdays: weekdays)
        }
    }
}
