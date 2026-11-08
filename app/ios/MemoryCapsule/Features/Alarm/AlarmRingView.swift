import SwiftUI

/// 앱 안 알람 화면(시니어). 시스템 알람(AlarmKit)과 별개로, 앱이 열려 있거나 알람을 눌러 들어왔을 때 보인다.
/// 문구를 기기 TTS로 2번 읽는다(Live 세션 사용 안 함). 확인 필요 일정만 "했어요" 버튼과 ack가 있다(앱 계획서 2.4).
struct AlarmRingView: View {
    let alarm: RingingAlarm
    let close: () -> Void
    @Environment(AppState.self) private var app
    @State private var bird = BirdModel()

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "alarm.fill").font(.system(size: 56)).foregroundStyle(Theme.green)
            Text(alarm.title).font(.system(size: 40, weight: .heavy)).multilineTextAlignment(.center)
            Text(alarm.message).font(.system(size: 26, weight: .semibold)).multilineTextAlignment(.center).lineSpacing(6)
            BirdView(model: bird).frame(maxWidth: 200)
            Spacer()
            if alarm.needsAck {
                Button("했어요") { Task { await done() } }
                    .buttonStyle(PrimaryButtonStyle()).frame(maxWidth: .infinity)
            }
            Button { speak() } label: { Label("다시 듣기", systemImage: "speaker.wave.2.fill") }
                .font(.title3.weight(.semibold)).frame(minHeight: 48)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .task {
            bird.setExpression(.happy)
            await speakTwice()
            if !alarm.needsAck {
                // 확인 불필요: 두 번 읽고 닫는다. ack를 보내지 않는다.
                AlarmScheduler.shared.markHandled(scheduleId: alarm.scheduleId, dueEpoch: alarm.dueEpoch)
                close()
            }
        }
        .onDisappear { Narrator.shared.stop() }
    }

    private func speak() { Narrator.shared.say("\(alarm.title). \(alarm.message)") }

    private func speakTwice() async {
        for _ in 0..<2 {
            speak()
            try? await Task.sleep(for: .milliseconds(600))
            while Narrator.shared.isSpeaking { try? await Task.sleep(for: .milliseconds(200)) }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func done() async {
        Narrator.shared.stop()
        await AlarmScheduler.shared.acknowledge(scheduleId: alarm.scheduleId, dueEpoch: alarm.dueEpoch, api: app.api, method: "button")
        close()
    }
}
