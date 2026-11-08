import Foundation
import AVFoundation

/// gpt-live-1 데이터 채널(`oai-events`)에서 앱이 쓰는 이벤트만 추린 것. PoC voice.mjs handle()/app.mjs event().
enum LiveEvent: Sendable {
    case started
    case inputDelta(id: String, text: String, startMs: Int)
    /// 턴 종료. 정확한 이벤트 이름은 Live 명세 확인 필요(app_spec 6장). 지금은 `session.input_transcript.done`으로 가정.
    case inputDone(startMs: Int, endMs: Int)
    case outputDelta(id: String, text: String, startMs: Int)
    case delegation(id: String)
    case usage(seconds: Double, final: Bool)
    case warning(String)
    case closed
}

enum LiveState: Equatable, Sendable { case idle, connecting, active, closing, ended(String?), error(String) }

@MainActor
protocol LiveVoice: AnyObject {
    var onEvent: (LiveEvent) -> Void { get set }
    var onState: (LiveState) -> Void { get set }
    /// 기억이 목소리 크기 0~1(입 움직임)
    func mouthLevel() -> Double
    func start(api: APIClient) async
    func stop()
    func send(json: [String: Any])
    var sessionId: String? { get }
    var maxSeconds: Int { get }
}

extension LiveVoice {
    /// R3 안전 문구 주입(backend 1.3). Live 명세 확인 전까지 PoC가 쓰는 `session.commentary.append` 형식.
    func injectSafety(_ text: String, delegationId: String?) {
        var event: [String: Any] = ["type": "session.commentary.append", "event_id": UUID().uuidString,
                                    "content": "다음 문장을 그대로 말한 뒤 기다리세요: \(text)"]
        if let delegationId { event["delegation_id"] = delegationId }
        send(json: event)
    }
}

/// 목 모드: PoC 미리보기 장면(app.mjs scenes)을 Live 이벤트처럼 흘려 판단 큐·표정·자막 흐름을 끝까지 확인.
@MainActor
final class MockLiveVoice: LiveVoice {
    var onEvent: (LiveEvent) -> Void = { _ in }
    var onState: (LiveState) -> Void = { _ in }
    private(set) var sessionId: String?
    private(set) var maxSeconds = 180
    private var task: Task<Void, Never>?
    private var speakingUntil = Date.distantPast
    /// 목 모드에서도 기억이 목소리를 들려주기 위해 기기 TTS로 읽는다(실제 연결에서는 gpt-live-1 음성).
    private let speaker = AVSpeechSynthesizer()

    private func speak(_ text: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)   // 무음 스위치와 무관하게 재생
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        u.rate = 0.45
        speaker.speak(u)
    }

    /// (지연ms, 기억이 말, 어르신 말)
    static let scenes: [(Int, String, String)] = [
        (0, "오늘은 어떤 하루를 보내셨어요?", ""),
        (1600, "", "오늘 손녀가 찾아왔는데…"),
        (2900, "", "오늘 손녀가 찾아왔는데, 같이 밥을 먹어서 참 좋았어요."),
        (5000, "함께 보내서 더 따뜻한 하루였겠어요.", ""),
        (7600, "", "그런데 집에 가고 나니까…"),
        (9000, "", "그런데 집에 가고 나니까, 조금 쓸쓸해졌어요."),
        (11200, "즐거웠던 만큼 빈자리가 느껴지셨겠어요.", ""),
        (13900, "", "그런데 내일도 또 온대요!"),
        (16000, "내일도 만나신다니 반가운 소식이네요.", ""),
    ]

    func mouthLevel() -> Double {
        let now = Date.now
        guard speaker.isSpeaking || now < speakingUntil else { return 0 }
        return max(0, sin(now.timeIntervalSinceReferenceDate * 1000 / 95)) * 0.65
    }

    func start(api: APIClient) async {
        onState(.connecting)
        guard let created = try? await api.createSession(.init(sdp: "", client: .init(platform: "ios", appVersion: AppInfo.version))) else {
            onState(.error("지금은 연결이 어려워요. 잠시 후 다시 해 주세요.")); return
        }
        sessionId = created.session.id; maxSeconds = created.session.maxSeconds
        onEvent(.started); onState(.active)
        task = Task { [weak self] in
            var elapsed = 0
            var lastInputStart = 0
            for (i, scene) in Self.scenes.enumerated() {
                try? await Task.sleep(for: .milliseconds(scene.0 - elapsed)); elapsed = scene.0
                guard let self, !Task.isCancelled else { return }
                if !scene.1.isEmpty {
                    self.speak(scene.1)
                    self.onEvent(.outputDelta(id: "o\(i)", text: scene.1, startMs: scene.0))
                }
                if !scene.2.isEmpty {
                    let isNewTurn = i == 0 || Self.scenes[i - 1].2.isEmpty
                    if isNewTurn { lastInputStart = scene.0 }
                    self.onEvent(.inputDelta(id: "i\(i)", text: scene.2, startMs: lastInputStart))
                    let next = i + 1 < Self.scenes.count ? Self.scenes[i + 1] : nil
                    if next == nil || !(next!.2.isEmpty == false) {
                        self.onEvent(.inputDone(startMs: lastInputStart, endMs: scene.0 + 800))
                    }
                }
                self.onEvent(.usage(seconds: Double(scene.0) / 1000 + 15, final: false))
            }
            try? await Task.sleep(for: .seconds(3))
            self?.onEvent(.usage(seconds: 22, final: true))
            self?.onEvent(.closed); self?.onState(.ended("미리보기 대화를 마쳤어요."))
        }
    }

    func stop() {
        task?.cancel(); task = nil
        speaker.stopSpeaking(at: .immediate)
        onEvent(.closed); onState(.ended("대화를 마쳤어요."))
    }
    /// 목 모드의 R3 안전 문구도 소리로 읽는다.
    func send(json: [String: Any]) {
        if json["type"] as? String == "session.commentary.append", let c = json["content"] as? String,
           let text = c.components(separatedBy: ": ").dropFirst().joined(separator: ": ").nilIfEmpty {
            speak(text)
        }
    }
}

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1" }
    static var useMock: Bool { (Bundle.main.object(forInfoDictionaryKey: "MC_USE_MOCK") as? String ?? "YES").uppercased() != "NO" }
    /// 연결한 백엔드 이름(기본 team). Config의 MC_BACKEND
    static var backend: String { Bundle.main.object(forInfoDictionaryKey: "MC_BACKEND") as? String ?? "team" }
    /// 백엔드별 Firebase 설정 파일. MemoryCapsule/Firebase/<이름>.plist, 없으면 예전 위치의 GoogleService-Info.plist
    static var firebasePlistPath: String? {
        let name = Bundle.main.object(forInfoDictionaryKey: "MC_FIREBASE_PLIST") as? String ?? ""
        return (name.isEmpty ? nil : Bundle.main.path(forResource: name, ofType: "plist"))
            ?? Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist")
    }
    static var apiBaseURL: URL { URL(string: Bundle.main.object(forInfoDictionaryKey: "MC_API_BASE_URL") as? String ?? "") ?? URL(string: "https://example.invalid")! }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
