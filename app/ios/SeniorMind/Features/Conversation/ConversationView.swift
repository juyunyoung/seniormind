import SwiftUI

/// 대화 화면: S01 대화 대기 · S02 대화 중 · S04 기억이의 답변(와이어프레임).
/// 구성: 오른쪽 위 "설정·도움" → 말풍선(기억이) → 캐릭터 → 어르신 자막 → 버튼.
/// R2는 화면 아래 상담 번호 카드, R3는 전체 안전 화면, 기억 제어는 대화 위 확인 창.
/// 어르신 화면에는 감정·위험 상태를 표시하지 않는다. 개발 패널은 DEBUG 빌드에서만.
struct ConversationView: View {
    @State var model: ConversationViewModel
    @Environment(AppState.self) private var app
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBar
                SpeechBubble(text: model.assistantText.isEmpty ? " " : model.assistantText)
                    .padding(.top, 8)
                    .animation(.easeOut(duration: 0.2), value: model.assistantText)
                BirdView(model: model.bird)
                    .frame(maxWidth: 340)
                    .padding(.top, 20)
                    .background(alignment: .bottom) {
                        Ellipse().fill(RadialGradient(colors: [Color(hex: 0x415F35, opacity: 0.12), .clear], center: .center, startRadius: 0, endRadius: 120))
                            .frame(width: 220, height: 24).offset(y: -10)
                    }
                if !model.callerText.isEmpty { callerBox.padding(.top, 16) }
                Text(model.statusText)
                    .font(.title3)
                    .foregroundStyle(model.isError ? Theme.error : Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 28)
                    .padding(.top, 18).padding(.bottom, 14)
                    .accessibilityAddTraits(.updatesFrequently)
                actions
                if model.isError { offlineHelp.padding(.top, 16) }
                if model.showHotline, let phrase = model.safety, phrase.level == .r2 { hotlineCard(phrase).padding(.top, 20) }
                if let notice = model.notice {
                    Text(notice).font(.footnote).foregroundStyle(Theme.muted).padding(.top, 12)
                }
                #if DEBUG
                DisclosureGroup("개발자 패널") { DeveloperPanel(model: model) }
                    .padding(.top, 40).tint(Theme.muted)
                #endif
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .sheet(isPresented: $showSettings) { SeniorSettingsView() }
        .sheet(isPresented: Binding(get: { model.memoryPrompt != nil }, set: { if !$0 { model.answerMemoryPrompt(false) } })) {
            MemoryConfirmView(control: model.memoryPrompt?.control ?? .none) { model.answerMemoryPrompt($0) }
                .presentationDetents([.medium])
                .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: $model.showSafetyScreen) {
            if let phrase = model.safety {
                SafetyView(phrase: phrase, guardianNotified: app.hasGuardian) { model.showSafetyScreen = false }
            }
        }
        .onAppear {
            if let name = app.displayName, !model.busy { model.assistantText = "\(name)님, 오늘 어떠셨어요?" }
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button { showSettings = true } label: {
                Text("설정·도움").font(.headline).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.secondaryFill, in: Capsule())
            }
            .foregroundStyle(Theme.green)
            .disabled(model.busy)
        }
        .padding(.vertical, 16)
    }

    private var callerBox: some View {
        Text(model.callerText)
            .font(.system(size: 22)).lineSpacing(5)
            .foregroundStyle(Theme.caller)
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: 520)
            .background(Theme.callerBox, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
            .accessibilityLabel("내가 한 말: \(model.callerText)")
    }

    private var actions: some View {
        Group {
            if model.busy {
                Button("대화 마치기") { model.end() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.state == .closing)
            } else {
                Button(model.isError ? "다시 연결하기" : "기억이와 대화하기") { model.connect() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    /// 연결 실패 안내: 상담 번호 바로가기(앱 계획서 1.9).
    private var offlineHelp: some View {
        let hotline = ConfigStore.shared.current.safety.hotline
        return Link(destination: URL(string: "tel://\(hotline.number.replacingOccurrences(of: "-", with: ""))")!) {
            Label("\(hotline.name) \(hotline.number)", systemImage: "phone.fill").font(.headline)
        }
        .foregroundStyle(Theme.green)
    }

    /// R2: 안전 문구 + 문구에 딸린 번호 버튼. 대화는 계속된다.
    private func hotlineCard(_ phrase: SafetyPhrase) -> some View {
        let safety = ConfigStore.shared.current.safety
        let numbers = (phrase.numbers?.isEmpty == false) ? phrase.numbers! : [safety.hotline.number]
        return VStack(spacing: 10) {
            Text(phrase.text).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            ForEach(numbers, id: \.self) { number in
                let name = safety.contacts?.first { $0.number == number }?.name ?? safety.hotline.name
                Link(destination: URL(string: "tel://\(number.replacingOccurrences(of: "-", with: ""))")!) {
                    Label("\(name) \(number)", systemImage: "phone.fill")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(.white)
                        .background(Theme.green, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding(18)
        .background(Theme.selectedFill, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// 기억 제어 확인(앱 계획서 1.7). 대화 위에 뜨는 확인 창. 이유는 묻지 않는다. 10초 무응답이면 "아니요".
struct MemoryConfirmView: View {
    let control: MemoryControl
    let answer: (Bool) -> Void
    @State private var remaining = 10

    private var question: String {
        switch control {
        case .delete: "방금 말씀하신 내용을 지울까요?"
        case .doNotShare: "이 이야기는 가족에게 보이지 않게 할까요?"
        case .doNotRemember: "이 이야기는 기억하지 않을까요?"
        case .correct: "방금 고쳐 말씀하신 대로 바꿀까요?"
        case .none: ""
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            Text(question).font(.system(size: 28, weight: .bold)).multilineTextAlignment(.center).padding(.top, 28)
            VStack(spacing: 12) {
                Button("네, 그렇게 해 주세요") { answer(true) }.buttonStyle(PrimaryButtonStyle())
                Button("아니요") { answer(false) }.buttonStyle(SecondaryButtonStyle())
            }
            Text("\(remaining)초 뒤에는 그대로 둘게요").font(.footnote).foregroundStyle(Theme.muted)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .task {
            while remaining > 0 { try? await Task.sleep(for: .seconds(1)); remaining -= 1 }
            answer(false)
        }
    }
}

#if DEBUG
/// 개발 빌드 전용: 표정·미리보기·사용량·알람 화면 시험.
struct DeveloperPanel: View {
    @Bindable var model: ConversationViewModel
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("네 가지 표정").font(.title3.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Expression.allCases, id: \.self) { e in
                    Button { model.tapExpression(e) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(e.title).font(.headline)
                            Text(e.subtitle).font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 17).padding(.horizontal, 12)
                        .background(model.expression == e ? Theme.selectedFill : .white, in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(model.expression == e ? Theme.selectedBorder : Theme.line))
                    }
                    .foregroundStyle(Color(hex: 0x34483A))
                    .disabled(model.busy)
                }
            }
            Button(model.previewing ? "미리보기 멈추기" : "대화에 반응하는 모습 보기") { model.togglePreview() }
                .buttonStyle(SecondaryButtonStyle()).frame(maxWidth: .infinity).disabled(model.busy)
            Button("알람 화면 보기") {
                app.ringing = RingingAlarm(scheduleId: "debug", dueEpoch: Int(Date.now.timeIntervalSince1970),
                                           title: "혈압약", message: "혈압약 드실 시간이에요", needsAck: true)
            }
            .buttonStyle(SecondaryButtonStyle()).frame(maxWidth: .infinity)
            Button("처음 실행 상태로") { app.resetForDebug() }
                .buttonStyle(SecondaryButtonStyle()).frame(maxWidth: .infinity)

            Divider().overlay(Theme.line)
            Text("지금의 반응과 사용량").font(.title3.bold())
            Picker("판단 간격", selection: $model.batchMs) {
                Text("1초 · 반응 우선").tag(1000)
                Text("2초 · 호출 절약 비교").tag(2000)
            }
            .disabled(model.busy)
            row("표정", model.expression.label)
            row("판단 소요 시간", model.stats.latencyMs.map { "\($0) ms" } ?? "실제 연결 후 측정")
            row("판단 요청 / 완료", "\(model.stats.requested) / \(model.stats.completed)회")
            row("반응 변경", "\(model.stats.applied)회")
            row("음성 사용량", model.usageSeconds.map { "\(Int($0))초" + (model.usageFinal ? " · 최종" : "") } ?? "—")
            row("음성 예상 비용", model.voiceCostText)
            row("판단 예상 비용", model.decisionCostText)
            HStack { Text("합계 · USD").font(.subheadline).foregroundStyle(Theme.muted); Spacer()
                Text(model.totalCostText).font(.title3.bold()).foregroundStyle(Theme.green) }
        }
        .padding(.top, 12)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).font(.subheadline).foregroundStyle(Theme.muted); Spacer(); Text(v).font(.subheadline.bold()) }
            .padding(.vertical, 4)
    }
}
#endif
