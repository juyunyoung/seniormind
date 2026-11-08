import SwiftUI

/// 대화 화면(와이어프레임 S01~S05). 캐릭터는 결정된 아기 새(디자인의 원형 자리).
/// - S01 홈: 말풍선 + 기억이. 기억이를 누르면 대화 시작.
/// - S02 듣는 중: 말풍선 + "• 듣는 중" + 어르신 자막 상자.
/// - S03 잠시만 기다려 주세요: "다시 말할래".
/// - S04 기억이 답변: 큰 말풍선.
/// - S05 연결을 다시 확인해요: "다시 이야기하기" / "홈으로 가기".
/// R2는 아래 상담 번호 카드, R3는 전체 안전 화면, 기억 제어는 대화 위 확인 창(와이어프레임 없음, 명세 필수).
struct ConversationView: View {
    @State var model: ConversationViewModel
    let router: SeniorRouter
    @Environment(AppState.self) private var app

    var body: some View {
        SeniorScaffold(onSettings: { router.push(.settings) }, settingsDisabled: model.busy) {
            SpeechBubble(text: bubbleText, size: model.stage == .answering ? 30 : 28)
                .padding(.top, model.stage == .home ? 60 : 24)
                .animation(.easeOut(duration: 0.2), value: bubbleText)
            Button { if model.stage == .home { model.connect() } } label: {
                BirdView(model: model.bird)
                    .frame(maxWidth: model.stage == .home || model.stage == .answering ? 300 : 220)
                    .padding(.top, 16)
            }
            .buttonStyle(.plain)
            .disabled(model.stage != .home)
            .accessibilityLabel(model.stage == .home ? "기억이와 이야기 시작하기" : "기억이")
            .accessibilityHint(model.stage == .home ? "두 번 누르면 대화를 시작해요" : "")

            if model.stage == .listening {
                Label("듣는 중", systemImage: "circle.fill")
                    .labelStyle(DotLabelStyle())
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.green)
                    .padding(.top, 14)
                    .accessibilityAddTraits(.updatesFrequently)
                if !model.callerText.isEmpty { callerBox.padding(.top, 14) }
            }
            if model.showHotline, let phrase = model.safety, phrase.level == .r2 { hotlineCard(phrase).padding(.top, 20) }
            #if DEBUG
            if model.stage == .error {   // 개발용: 실제 원인(서버 코드·메시지)을 작게 보여 준다
                Text("원인: \(model.statusText)\n서버: \(AppInfo.apiBaseURL.host() ?? "-") · \(AppInfo.backend)")
                    .font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding(.top, 12)
            }
            DisclosureGroup("개발자 패널") { DeveloperPanel(model: model) }
                .padding(.top, 40).tint(Theme.muted)
            #endif
        } bottom: {
            switch model.stage {
            case .waiting:
                if model.state == .active { Button("다시 말할래") { model.listenAgain() }.buttonStyle(PrimaryButtonStyle()) }
            case .error:
                Button("다시 이야기하기") { model.connect() }.buttonStyle(PrimaryButtonStyle())
                Button("홈으로 가기") { model.goHome() }.buttonStyle(SecondaryButtonStyle())
            case .listening, .answering:
                // 와이어프레임에는 없음: 음성 "그만할게"가 기본, 이 버튼은 대비용
                Button("대화 마치기") { model.end() }.buttonStyle(SecondaryButtonStyle()).disabled(model.state == .closing)
            case .home:
                EmptyView()
            }
        }
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
        .onAppear { model.onMicDenied = { router.push(.micOff) } }
    }

    private var bubbleText: String {
        switch model.stage {
        case .home: return app.displayName.map { "\($0)님,\n오늘 어떠셨어요?" } ?? "오늘 어떠셨어요?"
        case .waiting: return "잠시만 기다려 주세요"
        case .error: return "답변을 가져오지 못했어요.\n인터넷 연결을\n확인하고 다시\n이야기해 주세요."
        case .listening, .answering: return model.assistantText.isEmpty ? "오늘 어떠셨어요?" : model.assistantText
        }
    }

    private var callerBox: some View {
        Text(model.callerText)
            .font(.system(size: 23, weight: .medium)).lineSpacing(6)
            .foregroundStyle(Theme.text)
            .multilineTextAlignment(.center)
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Theme.callerBox, in: RoundedRectangle(cornerRadius: 26))
            .accessibilityLabel("내가 한 말: \(model.callerText)")
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

/// "• 듣는 중" 점 표시.
private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) { configuration.icon.font(.system(size: 8)); configuration.title }
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
