import SwiftUI
import AVFoundation
import UserNotifications

/// 화면에 쓰는 안내 문장을 기기 TTS로 읽어 주는 작은 도우미(어르신 화면 공통).
@MainActor
final class Narrator {
    static let shared = Narrator()
    private let speaker = AVSpeechSynthesizer()

    func say(_ text: String, rate: Float = 0.42) {
        speaker.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        u.rate = rate
        speaker.speak(u)
    }
    func stop() { speaker.stopSpeaking(at: .immediate) }
    var isSpeaking: Bool { speaker.isSpeaking }
}

/// S01 첫 실행: 호칭 입력(앱 계획서 1.0). 키보드 마이크로 말해서 입력해도 된다. 건너뛸 수 있다.
struct NameEntryView: View {
    @Environment(AppState.self) private var app
    @State private var name = ""
    @State private var bird = BirdModel()
    @FocusState private var focused: Bool
    private let question = "어떻게 불러 드릴까요?"

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)
            SpeechBubble(text: question)
            BirdView(model: bird).frame(maxWidth: 240)
            TextField("예: 영희", text: $name)
                .font(.system(size: 28, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.vertical, 16)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
                .focused($focused)
                .submitLabel(.done)
                .accessibilityLabel("부를 이름")
            Spacer()
            Button("이렇게 불러 주세요") { save(name) }
                .buttonStyle(PrimaryButtonStyle()).frame(maxWidth: .infinity)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("건너뛸게요") { save(nil) }
                .buttonStyle(SecondaryButtonStyle()).frame(maxWidth: .infinity)
        }
        .padding(24)
        .background(Theme.background)
        .onAppear { Narrator.shared.say(question) }
    }

    private func save(_ value: String?) {
        Narrator.shared.stop()
        if value != nil { bird.setExpression(.happy) }
        Task { await app.saveName(value) }
    }
}

/// 권한 안내(공통 화면 중 시니어용): 시스템 팝업 전에 왜 필요한지 먼저 알려 주고 차례로 요청한다.
struct PermissionPrimerView: View {
    @Environment(AppState.self) private var app
    @State private var busy = false

    private struct Item: Identifiable { let icon: String, title: String, detail: String; var id: String { title } }
    private let items: [Item] = [
        .init(icon: "mic.fill", title: "마이크", detail: "기억이와 목소리로 대화해요."),
        .init(icon: "bell.fill", title: "알림", detail: "보호자와 연결되면 소식을 알려 드려요."),
        .init(icon: "alarm.fill", title: "알람", detail: "약 드실 시간을 알람으로 알려 드려요."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("기억이가 쓰는 기능이에요").font(.system(size: 30, weight: .bold)).padding(.top, 32)
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: item.icon).font(.title).foregroundStyle(Theme.green).frame(width: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title).font(.title2.weight(.bold))
                        Text(item.detail).font(.title3).foregroundStyle(Theme.muted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Spacer()
            Text("다음 화면에서 '허용'을 눌러 주세요.").font(.title3).foregroundStyle(Theme.muted)
            Button("확인했어요") { Task { await request() } }
                .buttonStyle(PrimaryButtonStyle()).frame(maxWidth: .infinity).disabled(busy)
        }
        .padding(24)
        .background(Theme.background)
        .onAppear { Narrator.shared.say("기억이가 쓰는 기능이에요. 마이크, 알림, 알람을 허용해 주세요.") }
    }

    private func request() async {
        busy = true
        Narrator.shared.stop()
        _ = await AVAudioApplication.requestRecordPermission()
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        _ = await AlarmScheduler.shared.requestPermission()
        await app.registerDevice(fcmToken: PushTokenStore.token)
        app.permissionsAsked = true
        busy = false
    }
}

/// 말풍선(S01·S02·S04 공통).
struct SpeechBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 26, weight: .bold))
            .lineSpacing(5)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22).padding(.vertical, 16)
            .frame(maxWidth: 520)
            .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 22))
            .overlay(alignment: .bottom) {
                Triangle().fill(Theme.bubble).frame(width: 22, height: 12).offset(y: 11)
            }
            .accessibilityLabel("기억이: \(text)")
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath(); return p
    }
}
