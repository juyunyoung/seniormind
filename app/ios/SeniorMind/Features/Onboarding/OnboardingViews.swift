import SwiftUI
import AVFoundation

/// A01 · 누가 사용하시나요? (공통)
struct RoleSelectView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 20).padding(.top, 56)
            Text("누가 사용하시나요?")
                .font(.system(size: 30, weight: .heavy))
                .padding(.top, 56).padding(.bottom, 44)
            VStack(spacing: 20) {
                roleCard("시니어로 시작", "기억이와 편하게 대화해요") { app.choose(.senior) }
                roleCard("보호자로 시작", "가족의 안부를 살펴봐요") { app.choose(.guardian) }
            }
            .padding(.horizontal, 20)
            Spacer()
            Text("기억이는 AI 말벗이에요.").font(.system(size: 15)).foregroundStyle(Theme.muted).padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.startBackground)
        .foregroundStyle(Theme.text)
    }

    private func roleCard(_ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.system(size: 27, weight: .bold))
                    Text(detail).font(.system(size: 19)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("›").font(.system(size: 26, weight: .semibold))
            }
            .padding(.horizontal, 24).padding(.vertical, 34)
            .background(.white, in: RoundedRectangle(cornerRadius: 30))
            .overlay(RoundedRectangle(cornerRadius: 30).stroke(Theme.cardBorder))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// C01 · 대화 시작 동의(시니어). 홈 화면 위에 뜨는 확인 창.
/// 확인하면 대화에 필요한 동의 3종(목소리 전송·대화 보관·기억 카드)을 기록하고 마이크 권한(C02)을 묻는다.
/// 문구는 자리 표시용(작업 목록 L13 확정 후 교체, version "draft").
struct SeniorConsentView: View {
    @Environment(AppState.self) private var app
    @State private var checked = false
    @State private var showNotice = false
    @State private var busy = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("기억캡슐").font(.system(size: 16)).foregroundStyle(Theme.muted)
                Text("대화 시작 동의").font(.system(size: 28, weight: .bold))
                Text("기억이는 AI 말벗이에요.\n개인정보 처리 안내를 확인하고\n대화를 시작해 주세요.")
                    .font(.system(size: 20)).lineSpacing(5)
                Button("개인정보 처리 안내 보기") { showNotice = true }
                    .font(.system(size: 19, weight: .bold)).underline().foregroundStyle(Theme.green)
                Button { checked.toggle() } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: checked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 28)).foregroundStyle(checked ? Theme.green : Theme.muted)
                        Text("개인정보 처리 안내를 확인했어요").font(.system(size: 19)).multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(checked ? .isSelected : [])
                VStack(spacing: 12) {
                    Button("확인하고 시작") { accept() }.buttonStyle(PrimaryButtonStyle()).disabled(!checked || busy)
                    Button("나중에") { app.backToRoleSelect() }.buttonStyle(SecondaryButtonStyle())
                }
                .padding(.top, 6)
            }
            .padding(24)
            .background(.white, in: RoundedRectangle(cornerRadius: 30))
            .padding(.horizontal, 14).padding(.bottom, 24)
            .foregroundStyle(Theme.text)
        }
        .sheet(isPresented: $showNotice) { PrivacyNoticeView() }
    }

    private func accept() {
        busy = true
        Task { await app.seniorConsentAccepted(); busy = false }
    }
}

/// 개인정보 처리 안내(자리 표시 문구, L13 확정본으로 교체).
struct PrivacyNoticeView: View {
    @Environment(\.dismiss) private var dismiss
    private let items: [(String, String)] = [
        ("목소리 전송", "말씀하신 목소리는 인터넷으로 AI에 전송되어 대답을 만들어요. 녹음 파일로 저장하지 않아요."),
        ("대화 내용 보관", "대화 내용(글자)은 7일, 기분 판단 결과는 90일 동안만 보관해요. 보호자에게 대화 원문은 보이지 않아요."),
        ("기억 카드", "들려주신 이야기를 기억 카드로 남겨 다음 대화에서 이어가요. \"그 얘기는 잊어줘\"라고 하시면 지워요."),
        ("철회", "설정·도움 화면에서 언제든 동의를 거둘 수 있어요."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(items.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(items[i].0).font(.system(size: 22, weight: .bold))
                            Text(items[i].1).font(.system(size: 19)).lineSpacing(5)
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle("개인정보 처리 안내")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
    }
}

/// 동의 화면(공통). 앱 계획서 1.1·2.2: 어르신 1·2 필수, 3 선택 / 보호자 등록 때 4~7(5·6 필수, 4·7 선택) / 보호자 3종.
/// 문구는 자리 표시용. 작업 목록 L13 확정본으로 교체하고 version도 바꾼다(지금은 "draft").
struct ConsentStep: Identifiable {
    let type: ConsentType
    let title: String
    let body: String
    let required: Bool
    var id: String { type.rawValue }

    static let senior: [ConsentStep] = [
        .init(type: .voiceTransfer, title: "목소리가 인터넷으로 전송돼요",
              body: "기억이는 AI 말벗이에요. 말씀하신 목소리는 인터넷으로 전송되어 AI가 듣고 대답해요. 녹음 파일로 저장하지 않아요.", required: true),
        .init(type: .transcriptStore, title: "대화 내용을 잠시 보관해요",
              body: "대화 내용(글자)과 기분 판단 결과를 정해진 기간 동안만 서버에 보관해요. 보호자에게 대화 원문은 보이지 않아요.", required: true),
        .init(type: .memoryCard, title: "이야기를 기억 카드로 남겨요",
              body: "들려주신 이야기를 '기억 카드'로 남겨 다음 대화에서 이어가요. \"그 얘기는 잊어줘\"라고 하시면 지울 수 있어요.", required: false),
    ]
    static let seniorGuardian: [ConsentStep] = [
        .init(type: .sensitive, title: "힘든 신호를 알릴 수 있어요",
              body: "대화 중 위험한 신호가 있으면 보호자께 알릴 수 있어요. 대화 원문은 보내지 않아요.", required: false),
        .init(type: .guardianShare, title: "보호자에게 요약이 보여요",
              body: "보호자께는 기분 요약과 알림만 보여요.", required: true),
        .init(type: .scheduleShare, title: "약 드실 시간을 함께 챙겨요",
              body: "보호자가 등록한 알림과, 알림을 확인하셨는지가 보호자께 보여요.", required: true),
        .init(type: .guardianTopicShare, title: "이야기 나눈 주제를 보여 드려요",
              body: "기억이와 나눈 이야기의 주제 이름만 보호자께 보여요. 대화 내용은 보이지 않아요.", required: false),
    ]
    /// 문구 버전. L13 확정 전까지 draft.
    static let version = "draft"
    static let guardian: [ConsentStep] = [
        .init(type: .guardianTerms, title: "보호자 이용 약관", body: "기억의 캡슐 보호자 이용 약관에 동의해 주세요.", required: true),
        .init(type: .guardianDataView, title: "어르신 요약 정보 보기",
              body: "연결한 어르신의 기분 요약·알림·일정 확인 기록을 봐요. 대화 원문은 보이지 않아요.", required: true),
        .init(type: .guardianScheduleManage, title: "일정 등록과 확인 기록",
              body: "어르신의 알림을 등록하고, 확인 기록을 볼 수 있어요. 복약 지도나 진단은 하지 않아요.", required: true),
    ]
}

struct ConsentFlowView: View {
    let role: UserRole
    var steps: [ConsentStep]? = nil
    var linkedSeniorId: String? = nil
    var onDone: (() -> Void)? = nil

    @Environment(AppState.self) private var app
    @State private var index = 0
    @State private var speaker = AVSpeechSynthesizer()

    private var list: [ConsentStep] { steps ?? (role == .senior ? ConsentStep.senior : ConsentStep.guardian) }

    var body: some View {
        let step = list[index]
        VStack(alignment: .leading, spacing: 24) {
            Text("\(index + 1) / \(list.count)").font(.headline).foregroundStyle(Theme.muted)
            Text(step.title).font(.system(size: 30, weight: .bold))
            Text(step.body).font(.title3).lineSpacing(6)
            Spacer()
            Button("동의해요") { answer(true) }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: .infinity)
            if !step.required {
                Button("나중에 할게요") { answer(false) }.buttonStyle(SecondaryButtonStyle()).frame(maxWidth: .infinity)
            }
            Button { speak(step) } label: { Label("다시 듣기", systemImage: "speaker.wave.2.fill") }
                .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(24)
        .background(Theme.background)
        .onAppear { speak(step) }
        .onChange(of: index) { _, _ in speak(list[index]) }
    }

    private func speak(_ step: ConsentStep) {
        speaker.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: "\(step.title). \(step.body)")
        u.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        u.rate = 0.42
        speaker.speak(u)
    }

    private func answer(_ granted: Bool) {
        let step = list[index]
        Task {
            try? await app.api.postConsent(.init(type: step.type, version: ConsentStep.version, granted: granted,
                                                 method: "screen_tap", linkedSeniorId: linkedSeniorId))
        }
        UserDefaults.standard.set(granted, forKey: "mc.consent.\(step.type.rawValue)")
        if index + 1 < list.count { index += 1 } else {
            speaker.stopSpeaking(at: .immediate)
            if let onDone { onDone() } else { app.consentFinished(role) }
        }
    }
}
