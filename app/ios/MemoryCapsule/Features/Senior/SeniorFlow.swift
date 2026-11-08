import SwiftUI
import Observation

/// 시니어 화면 이동. 와이어프레임 흐름: S01 홈 ↔ S08 설정·도움 → S13 / P01 → P02·P03 → P05·P06.
enum SeniorRoute: Hashable {
    case settings          // S08 말로 조작하기
    case speed             // S13 말하는 속도
    case manage            // 연결된 보호자·동의 관리(와이어프레임 없음, 철회 수단으로 필요)
    case pairConsent       // 보호자 연결 전 동의(와이어프레임 없음, 서버 필수)
    case pairMenu          // P01 보호자에게 보여주세요
    case pairQR            // P02 이 QR을 읽어주세요
    case pairCode          // P03 이 번호를 입력해 주세요
    case pairDone          // P05 보호자와 연결됐어요
    case pairExpired       // P06 새 번호를 보여드릴게요
    case micOff            // C03 마이크가 꺼져 있어요
}

@Observable @MainActor
final class SeniorRouter {
    var stack: [SeniorRoute] = []
    var top: SeniorRoute? { stack.last }
    func push(_ r: SeniorRoute) { stack.append(r) }
    func pop() { if !stack.isEmpty { stack.removeLast() } }
    func home() { stack.removeAll() }
    /// 같은 단계 안에서 화면만 바꾼다(P02 ↔ P03 등).
    func replace(_ r: SeniorRoute) { if stack.isEmpty { stack = [r] } else { stack[stack.count - 1] = r } }
}

/// 시니어 화면 전체. 첫 실행: (C01 동의 → C02 마이크) → C03(거절 시) → C04 이름 → S01 홈.
struct SeniorRootView: View {
    @Environment(AppState.self) private var app
    @State private var model: ConversationViewModel?
    @State private var router = SeniorRouter()
    @State private var pairing = PairingSession()

    var body: some View {
        @Bindable var app = app
        Group {
            if app.micDenied { MicOffView { app.micDenied = false } }
            else if !app.nameAsked { NameEntryView() }
            else if let top = router.top { screen(top).transition(.opacity) }
            else if let model { ConversationView(model: model, router: router) }
            else { Theme.background }
        }
        .animation(.easeInOut(duration: 0.2), value: router.stack)
        .environment(router)
        .environment(pairing)
        .onAppear { if model == nil { model = ConversationViewModel(api: app.api, voice: app.makeLiveVoice()) } }
        .fullScreenCover(item: $app.ringing) { alarm in
            AlarmRingView(alarm: alarm) { app.ringing = nil }
        }
    }

    @ViewBuilder private func screen(_ r: SeniorRoute) -> some View {
        switch r {
        case .settings: SeniorSettingsView()
        case .speed: SpeechRateView()
        case .manage: SeniorManageView()
        case .pairConsent:
            ConsentFlowView(role: .senior, steps: ConsentStep.seniorGuardian) { router.replace(.pairMenu) }
        case .pairMenu: PairMenuView()
        case .pairQR: PairQRView()
        case .pairCode: PairCodeView()
        case .pairDone: PairDoneView()
        case .pairExpired: PairExpiredView()
        case .micOff: MicOffView { router.pop() }
        }
    }
}
