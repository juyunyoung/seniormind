import SwiftUI
import AVFoundation
import UIKit

/// 화면에 쓰는 안내 문장을 기기 TTS로 읽어 주는 도우미(시니어 화면 공통).
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
        u.rate = AppState.shared.speechRate == "slow" ? rate - 0.08 : rate
        speaker.speak(u)
    }
    func stop() { speaker.stopSpeaking(at: .immediate) }
    var isSpeaking: Bool { speaker.isSpeaking }
}

/// C04 · 어떻게 불러드릴까요? — 이름(필수)·나이(선택). 키보드 마이크로 말해서 입력해도 된다.
struct NameEntryView: View {
    @Environment(AppState.self) private var app
    @State private var name = ""
    @State private var age = ""
    @State private var saving = false
    @State private var bird = BirdModel()
    private let question = "어떻게\n불러드릴까요?"

    var body: some View {
        SeniorScaffold(onBack: { app.backToRoleSelect() }) {
            SpeechBubble(text: question, size: 32)
            BirdView(model: bird).frame(width: 150, height: 150).padding(.top, 18).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                field("이름", text: $name, placeholder: "예: 김영희", keyboard: .default)
                field("나이 (선택)", text: $age, placeholder: "예: 72", keyboard: .numberPad)
            }
            .padding(.top, 20)
        } bottom: {
            Button("입력했어") { save() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
        }
        .onAppear { Narrator.shared.say("어떻게 불러드릴까요?") }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 19, weight: .bold))
            TextField(placeholder, text: text)
                .font(.system(size: 22))
                .keyboardType(keyboard)
                .padding(.horizontal, 16).frame(minHeight: 58)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.selectedBorder, lineWidth: 1.5))
                .accessibilityLabel(label)
        }
        .padding(.bottom, 8)
    }

    private func save() {
        saving = true
        Narrator.shared.stop()
        bird.setExpression(.happy)
        Task { await app.saveName(name, age: Int(age.filter(\.isNumber))); saving = false }
    }
}

/// C03 · 마이크가 꺼져 있어요. C02에서 거절했거나, 대화를 시작하려는데 권한이 없을 때.
struct MicOffView: View {
    let onDone: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var bird = BirdModel()

    var body: some View {
        SeniorScaffold(onBack: onDone) {
            SpeechBubble(text: "기억이와 이야기하려면\n휴대폰 설정에서\n마이크를 켜 주세요.")
            BirdView(model: bird).frame(width: 150, height: 150).padding(.top, 24).accessibilityHidden(true)
        } bottom: {
            Button("마이크 권한 다시 확인") { openSettings() }.buttonStyle(PrimaryButtonStyle())
            Button("처음 화면으로 돌아가기", action: onDone).buttonStyle(SecondaryButtonStyle())
        }
        .onAppear { bird.setExpression(.empathy); Narrator.shared.say("기억이와 이야기하려면 휴대폰 설정에서 마이크를 켜 주세요.") }
        .onChange(of: scenePhase) { _, phase in
            // 설정 앱에서 돌아왔을 때 권한이 켜졌으면 바로 넘어간다
            if phase == .active, AVAudioApplication.shared.recordPermission == .granted { onDone() }
        }
    }

    private func openSettings() {
        if AVAudioApplication.shared.recordPermission == .undetermined {
            Task { if await AVAudioApplication.requestRecordPermission() { onDone() } }
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
