import Foundation
import Observation
import AVFoundation

/// 대화 화면(S01 대기·S02 대화 중·S04 답변) 상태. 팀 문서 앱 계획서 1.2~1.7.
@Observable @MainActor
final class ConversationViewModel {
    // 화면 값(PoC index.html의 id와 대응)
    /// 와이어프레임 단계: S01 홈 · S02 듣는 중 · S03 잠시만 기다려 주세요 · S04 기억이 답변 · S05 연결 다시 확인
    enum Stage: Equatable { case home, listening, waiting, answering, error }
    var stage: Stage = .home
    /// 대화 시작 전 마이크 권한이 없으면 C03으로 보낸다.
    @ObservationIgnored var onMicDenied: () -> Void = {}
    @ObservationIgnored private var idleTask: Task<Void, Never>?

    var assistantText = "오늘 어떠셨어요?"                  // 말풍선(기억이)
    var callerText = ""                                       // 어르신 자막
    var statusText = "버튼을 누르고 편하게 말씀해 주세요." 
    var isError = false
    var modeText = "모션 미리보기"                            // #mode
    var state: LiveState = .idle
    var expression: Expression = .neutral
    var previewing = false
    var notice: String?                                       // #connectionNotice
    /// 오류 화면 말풍선에 보일 서버 안내(하루 한도·업데이트 필요). nil이면 기본 문구
    var errorBubble: String?
    // R3·기억 제어
    var safety: SafetyPhrase?
    var showHotline = false          // R2: 화면 아래 상담 번호 카드
    var showSafetyScreen = false     // R3: 전체 안전 화면
    var memoryPrompt: (control: MemoryControl, assessmentId: String, targetUtteranceId: String?)?
    /// 기억 제어 확인 창의 단계. 지웠다는 안내는 서버가 성공(204)을 돌려준 뒤에만 보인다.
    enum MemoryPhase: Equatable { case asking, sending, done, failed, unsupported }
    var memoryPhase: MemoryPhase = .asking
    // 사용량(PoC readout)
    var stats = DecisionQueue.Stats()
    var usageSeconds: Double?
    var usageFinal = false
    var batchMs = 1000

    let bird: BirdModel
    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var voice: LiveVoice
    @ObservationIgnored private var queue: DecisionQueue?
    @ObservationIgnored private let motion: ReactionMotion
    @ObservationIgnored private var previewTasks: [Task<Void, Never>] = []

    @ObservationIgnored private var inputParts: [(id: String, start: Int, text: String)] = []
    @ObservationIgnored private var outputParts: [(id: String, start: Int, text: String)] = []
    @ObservationIgnored private var transcriptLog: [TranscriptPart] = []
    @ObservationIgnored private var turnSeq = 0
    /// 아직 끝나지 않은 발화의 자막 조각, 말이 멈췄는지 보는 타이머
    @ObservationIgnored private var openTurn: [(id: String, start: Int, text: String)] = []
    @ObservationIgnored private var turnTimer: Task<Void, Never>?
    @ObservationIgnored private var startedAt: Date?

    var busy: Bool { [.connecting, .active, .closing].contains(state) }

    init(api: APIClient, voice: LiveVoice) {
        self.api = api
        self.voice = voice
        let bird = BirdModel()
        self.bird = bird
        self.motion = ReactionMotion(bird: bird)
        bird.mouthLevel = { [weak self] in
            guard let self else { return 0 }
            return self.previewMouth ? max(0, sin(Date.now.timeIntervalSinceReferenceDate * 1000 / 95)) * 0.65 : self.voice.mouthLevel()
        }
        motion.onFace = { [weak self] in self?.expression = $0 }
        voice.onEvent = { [weak self] in self?.handle($0) }
        voice.onState = { [weak self] in self?.apply($0) }
    }
    @ObservationIgnored private var previewMouth = false
    @ObservationIgnored private var lastSafetyId: String?
    /// 대화 마치기: 요청 시각과 기억이의 마지막 말 시각(작별 인사가 끝나면 닫는다)
    @ObservationIgnored private var endRequestedAt: Date?
    @ObservationIgnored private var lastOutputAt: Date?
    @ObservationIgnored private var endTask: Task<Void, Never>?

    // MARK: - 표정 버튼·미리보기 (PoC 오른쪽 패널)

    func pose(_ e: Expression) {
        bird.setExpression(e); expression = e
    }

    func tapExpression(_ e: Expression) {
        clearPreview(); pose(e); statusText = "표정 미리보기 · 실제 음성 연결 전입니다."
    }

    func togglePreview() {
        if previewing { clearPreview(); pose(.neutral); statusText = "미리보기를 멈췄어요."; return }
        previewing = true
        statusText = "정해진 대화 예시 · API를 사용하지 않아요."
        let expressions: [Expression] = [.neutral, .neutral, .happy, .happy, .neutral, .empathy, .empathy, .surprised, .happy]
        let assistant = ["오늘은 어떤 하루를 보내셨어요?", "오늘은 어떤 하루를 보내셨어요?", "오늘은 어떤 하루를 보내셨어요?",
                         "함께 보내서 더 따뜻한 하루였겠어요.", "함께 보내서 더 따뜻한 하루였겠어요.", "함께 보내서 더 따뜻한 하루였겠어요.",
                         "즐거웠던 만큼 빈자리가 느껴지셨겠어요.", "즐거웠던 만큼 빈자리가 느껴지셨겠어요.", "내일도 만나신다니 반가운 소식이네요."]
        let caller = ["", "오늘 손녀가 찾아왔는데…", "오늘 손녀가 찾아왔는데, 같이 밥을 먹어서 참 좋았어요.",
                      "오늘 손녀가 찾아왔는데, 같이 밥을 먹어서 참 좋았어요.", "그런데 집에 가고 나니까…",
                      "그런데 집에 가고 나니까, 조금 쓸쓸해졌어요.", "그런데 집에 가고 나니까, 조금 쓸쓸해졌어요.",
                      "그런데 내일도 또 온대요!", "그런데 내일도 또 온대요!"]
        let delays = [0, 1600, 2900, 5000, 7600, 9000, 11200, 13900, 16000]
        for i in delays.indices {
            previewTasks.append(Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(delays[i]))
                guard let self, !Task.isCancelled else { return }
                self.pose(expressions[i])
                self.assistantText = assistant[i]
                self.callerText = caller[i].isEmpty ? "잠시 후 예시 대화가 시작돼요." : caller[i]
                self.previewMouth = [0, 3, 6, 8].contains(i)
            })
        }
        previewTasks.append(Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(19000))
            guard let self, !Task.isCancelled else { return }
            self.clearPreview(); self.pose(.neutral); self.statusText = "미리보기를 마쳤어요. 네 표정을 직접 눌러볼 수 있어요."
        })
    }

    private func clearPreview() {
        previewTasks.forEach { $0.cancel() }; previewTasks.removeAll(); previewing = false; previewMouth = false
    }

    // MARK: - 연결

    func connect() {
        guard AVAudioApplication.shared.recordPermission == .granted else {
            if AVAudioApplication.shared.recordPermission == .undetermined {
                Task { if await AVAudioApplication.requestRecordPermission() { self.connect() } else { self.onMicDenied() } }
            } else { onMicDenied() }
            return
        }
        stage = .waiting
        clearPreview(); motion.reset(); pose(.neutral)
        inputParts = []; outputParts = []; transcriptLog = []; turnSeq = 0; openTurn = []; turnTimer?.cancel(); turnTimer = nil
        assistantText = ""; callerText = ""; usageSeconds = nil; usageFinal = false; stats = .init()
        safety = nil; showHotline = false; showSafetyScreen = false; memoryPrompt = nil; memoryPhase = .asking; lastSafetyId = nil
        startedAt = .now
        endRequestedAt = nil; lastOutputAt = nil; endTask?.cancel(); endTask = nil
        Task { await voice.start(api: api) }
    }

    func end() { voice.stop() }

    /// S03 "다시 말할래": 기다리던 응답을 두고 다시 듣는 화면으로.
    func listenAgain() { stage = .listening }
    /// S05 "홈으로 가기"
    func goHome() { stage = .home; isError = false }

    private func apply(_ s: LiveState) {
        state = s
        isError = false
        switch s {
        case .connecting: notice = nil; statusText = "마이크와 목소리를 연결하고 있어요."
        case .active:
            stage = .listening
            statusText = "연결됐어요. 편하게 말씀해 주세요."
            if let id = voice.sessionId {
                queue = DecisionQueue(api: api, sessionId: id, batchMs: batchMs,
                                      onResult: { [weak self] r, final, uid in self?.applyDecision(r, final: final, utteranceId: uid) },
                                      onStats: { [weak self] in self?.stats = $0 })
            }
        case .closing: statusText = "대화를 마무리하고 있어요."; queue?.stop(); motion.stop()
        case .ended(let detail):
            statusText = detail ?? "대화를 마쳤어요."
            stage = .home
            finishSession(reason: "user")
        case .error(let message):
            isError = true; statusText = message
            // 하루 한도(429 daily_limit)·앱 업데이트 필요(426)는 서버 안내 문구를 말풍선에 그대로 보여 준다
            errorBubble = ["오늘 대화 한도", "최신 버전"].contains(where: message.contains) ? message.components(separatedBy: " (").first : nil
            stage = .error
            finishSession(reason: "error")
        case .idle: break
        }
        modeText = busy ? "실제 음성 대화" : "모션 미리보기"
        if !busy { pose(.neutral) }
    }

    private func finishSession(reason: String) {
        endTask?.cancel(); endTask = nil; endRequestedAt = nil
        finalizeTurn(endMs: nil, requestDecision: false)   // 마지막 말이 자막 기록에서 빠지지 않게(판단은 이미 닫힘)
        queue?.stop(); queue = nil; motion.stop()
        guard let id = voice.sessionId, !transcriptLog.isEmpty || startedAt != nil else { return }
        let duration = Int(usageSeconds ?? Date.now.timeIntervalSince(startedAt ?? .now))
        // 서버 규칙: duration 0~86400, usage는 seconds가 있을 때만, 자막은 공백 없는 줄만 최대 2000줄(줄당 16000자)
        let parts = currentTranscript()
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { p -> TranscriptPart in
                var p = p; p.text = String(p.text.prefix(16000)); p.startMs = max(0, p.startMs); p.endMs = max(p.startMs, p.endMs); return p
            }
        let body = SessionEndRequest(endReason: reason, durationSec: min(max(duration, 0), 86400),
                                     usage: usageSeconds.map { .init(seconds: min(max($0, 0), 86400)) },
                                     transcript: Array(parts.suffix(2000)))
        startedAt = nil
        Task { [api] in await Self.sendEnd(api: api, id: id, body) }
    }

    /// 세션 종료 전송. 서버는 마지막 판단이 아직 처리 중이면 409(decision_in_progress), 바쁘면 503을 돌려준다.
    /// 그때는 2·4·8초 뒤 같은 요청을 다시 보낸다(같은 세션 종료는 서버가 한 번만 처리).
    /// 409 utterance_conflict(발화 충돌)·404 등 그 밖의 오류는 다시 보내지 않는다.
    private static func sendEnd(api: APIClient, id: String, _ body: SessionEndRequest) async {
        for delay in [0, 2, 4, 8] {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            do { try await api.endSession(id: id, body); return }
            catch APIError.server(let status, let code, _) where status == 503 || (status == 409 && code == "decision_in_progress") { continue }
            catch is URLError { continue }
            catch { return }
        }
    }

    // MARK: - 이벤트

    private func handle(_ e: LiveEvent) {
        switch e {
        case .started: break
        case .inputDelta(let id, let text, let start):
            if !inputParts.contains(where: { $0.id == id }) {
                inputParts.append((id, start, text))
                openTurn.append((id, start, text))
            }
            inputParts.sort { $0.start < $1.start }
            if inputParts.count > 160 { inputParts.removeFirst(inputParts.count - 160) }
            callerText = currentTurn()
            stage = .listening
            statusText = "말씀에 귀 기울이고 있어요."
            queue?.push(input: inputText(), output: outputText())
            // 말이 2초 멈추면 한 발화가 끝난 것으로 본다(턴 종료 이벤트가 오지 않아도 판단·자막이 저장되게)
            turnTimer?.cancel()
            turnTimer = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(2000))
                guard let self, !Task.isCancelled else { return }
                self.finalizeTurn(endMs: nil)
                if self.stage == .listening { self.stage = .waiting }
            }
        case .inputDone(_, let end):
            finalizeTurn(endMs: end)
            stage = .waiting
        case .outputDelta(let id, let text, let start):
            finalizeTurn(endMs: nil)        // 기억이가 대답을 시작했으면 어르신 발화는 끝난 것
            let isNew = !outputParts.contains(where: { $0.id == id })
            if isNew { outputParts.append((id, start, text)) }
            outputParts.sort { $0.start < $1.start }
            assistantText = outputParts.filter { $0.start >= (outputParts.last?.start ?? 0) - 15000 }.map(\.text).joined()
            // 기억이 자막은 몇 글자씩 잘게 들어온다. 연달아 들어온 조각은 종료 자막에서 한 줄로 합친다
            // (팀 서버 종료 API는 최대 2000줄, 조각마다 한 줄이면 금방 넘는다).
            if isNew {
                if let last = transcriptLog.indices.last, transcriptLog[last].direction == "output" {
                    transcriptLog[last].text += text
                    transcriptLog[last].endMs = max(transcriptLog[last].endMs, start)
                } else {
                    transcriptLog.append(.init(direction: "output", utteranceId: nil, text: text, startMs: start, endMs: start))
                }
            }
            statusText = "기억이가 이야기하고 있어요."
            stage = .answering
            lastOutputAt = .now
            idleTask?.cancel()
            idleTask = Task { [weak self] in   // 말이 1.8초 끊기면 다시 듣는 화면
                try? await Task.sleep(for: .milliseconds(1800))
                guard let self, !Task.isCancelled, self.stage == .answering, self.busy else { return }
                self.stage = .listening; self.callerText = ""
            }
        case .delegation:
            break  // 회상 중계(app_spec 1.5)는 P2에서 위임 방식 확정 후
        case .usage(let seconds, let final):
            usageSeconds = seconds; usageFinal = final
        case .warning:
            notice = "음성 API에서 처리하지 못한 요청이 있어요. 연결은 유지하고 있습니다."
        case .closed: break
        }
    }

    private func applyDecision(_ r: DecisionResponse, final: Bool, utteranceId: String) {
        // needs_review(risk_level: unknown)면 중립 유지, 화면 변화 없음(서버가 재시도)
        guard r.assessmentStatus != "needs_review", r.riskLevel != .unknown else { return }
        let elevated = r.riskLevel == .r2 || r.riskLevel == .r3
        if r.safetyOverride == true {
            motion.lockEmpathy()                 // 안전 문구 중에는 공감 고정(앱 계획서 1.3)
        } else {
            if !elevated { motion.unlock() }
            if motion.accept(r.reaction) { queue?.countApplied() }
        }
        if elevated {
            // R2·R3 모두 고정 안전 문구. 문구·번호는 항상 설정값(앱 계획서 1.6).
            let phrase = ConfigStore.shared.safetyPhrase(id: r.safetyPhraseId, level: r.riskLevel)
            safety = phrase
            showHotline = true
            if let phrase, phrase.id != lastSafetyId {
                lastSafetyId = phrase.id
                voice.injectSafety(phrase.text, delegationId: nil)
                if r.riskLevel == .r3 { showSafetyScreen = true }
            }
        }
        // 기억 제어: 서버는 완료 판단에서만 알려 주고, 지금 실행되는 것은 "방금 한 말 지우기"(DELETE)뿐이다.
        // 이미 처리된(executed·cancelled) 판단을 다시 받았을 때는 확인 창을 또 띄우지 않는다.
        if final, r.memoryControl != .none, let aid = r.assessmentId, memoryPrompt == nil,
           r.memoryControlStatus == nil || r.memoryControlStatus == "pending" {
            if r.memoryControl == .delete {
                memoryPhase = .asking
                memoryPrompt = (r.memoryControl, aid, previousInputUtterance(before: utteranceId))
            } else {
                // 가족에게 보이지 않기·기억하지 않기·고치기는 서버가 아직 실행하지 못한다. 된 것처럼 보이지 않게 알린다.
                memoryPhase = .unsupported
                memoryPrompt = (r.memoryControl, aid, nil)
                closeMemoryPrompt(after: 4, assessmentId: aid)
            }
        }
        // 대화 마치기: 위험 신호·기억 제어 확인이 있으면 끝내지 않는다(안전 대응 우선)
        if elevated || memoryPrompt != nil { cancelEnd() }
        else if final, r.endIntent == "END" { requestEnd() }
    }

    // MARK: - 대화 마치기("나 쉴게", "그만 하자", "자자")

    /// 서버가 마치려는 뜻(end_intent)을 알려 주기 전까지 쓰는 임시 판단. 짧은 말에 작별 표현이 있을 때만.
    /// 긴 이야기 속의 "들어가서", "쉬었어" 같은 말로 끊기지 않게 25자 이하만 본다.
    static func soundsLikeFarewell(_ text: String) -> Bool {
        let t = text.replacingOccurrences(of: " ", with: "")
        guard t.count <= 25 else { return false }
        let phrases = ["그만할게", "그만할께", "그만하자", "이제그만", "끝내자", "쉴게", "쉴께", "자자", "잘게", "잘께", "자야겠",
                       "들어가", "끊을게", "끊을께", "끊자", "다음에또", "나중에또", "잘있어", "안녕히"]
        return phrases.contains { t.contains($0) }
    }

    /// 기억이의 작별 인사가 끝나면(1.8초 동안 새 말이 없으면) 대화를 닫는다. 인사가 오지 않아도 8초 뒤에는 닫는다.
    private func requestEnd() {
        guard endRequestedAt == nil, busy else { return }
        let requested = Date.now
        endRequestedAt = requested
        statusText = "대화를 마무리하고 있어요."
        endTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !Task.isCancelled, self.busy else { return }
                let now = Date.now
                let saidGoodbye = (self.lastOutputAt ?? .distantPast) > requested
                let quiet = now.timeIntervalSince(self.lastOutputAt ?? requested) > 1.8
                if (saidGoodbye && quiet) || now.timeIntervalSince(requested) > 8 {
                    self.end()
                    return
                }
            }
        }
    }

    private func cancelEnd() { endTask?.cancel(); endTask = nil; endRequestedAt = nil }

    /// 지우려는 대상: 지워 달라는 말 바로 앞의 어르신 발화(서버도 같은 발화를 대상으로 고정한다).
    private func previousInputUtterance(before utteranceId: String) -> String? {
        let inputs = transcriptLog.filter { $0.direction == "input" }
        guard let i = inputs.firstIndex(where: { $0.utteranceId == utteranceId }), i > 0 else { return nil }
        return inputs[i - 1].utteranceId
    }

    func answerMemoryPrompt(_ confirmed: Bool) {
        guard let p = memoryPrompt, memoryPhase == .asking else { return }
        let request = MemoryControlRequest(assessmentId: p.assessmentId, confirmed: confirmed, scope: "last_utterance", targetCardIds: [])
        guard confirmed else {
            // "아니요"·10초 무응답: 창을 닫고 취소만 알린다(원문·카드는 그대로)
            memoryPrompt = nil
            Task { [api] in try? await api.memoryControl(request) }
            return
        }
        memoryPhase = .sending
        Task { [weak self, api] in
            var done = false
            // 같은 확인 요청은 다시 보내도 된다(서버 멱등). 저장 장애(503)·통신 오류일 때만 한 번 더.
            for attempt in 0..<2 {
                do { try await api.memoryControl(request); done = true; break }
                catch {
                    let retryable = (error as? APIError)?.status == 503 || error is URLError
                    if attempt == 0, retryable { try? await Task.sleep(for: .seconds(1)); continue }
                    break
                }
            }
            guard let self, self.memoryPrompt?.assessmentId == p.assessmentId else { return }
            if done { self.forgetLocally(p.targetUtteranceId) }
            self.memoryPhase = done ? .done : .failed
            self.closeMemoryPrompt(after: 3, assessmentId: p.assessmentId)
        }
    }

    private func closeMemoryPrompt(after seconds: Int, assessmentId: String) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.memoryPrompt?.assessmentId == assessmentId else { return }
            self.memoryPrompt = nil; self.memoryPhase = .asking
        }
    }

    /// 서버에서 지운 발화를 앱이 들고 있는 기록에서도 뺀다(종료 자막·다음 판단 문맥으로 다시 보내지 않게).
    private func forgetLocally(_ utteranceId: String?) {
        guard let utteranceId else { return }
        transcriptLog.removeAll { $0.direction == "input" && $0.utteranceId == utteranceId }
        inputParts = []
        callerText = ""
    }

    // MARK: - 자막 조립

    /// 아직 끝나지 않은 발화(마지막 턴 종료 뒤에 들어온 입력 자막 조각들)
    private func currentTurn() -> String {
        openTurn.sorted { $0.start < $1.start }.map(\.text).joined()
    }

    /// 발화 하나를 끝낸다: 자막 기록에 넣고 완료 판단(final)을 요청한다.
    /// 부르는 때: 턴 종료 이벤트, 기억이가 대답을 시작할 때, 말이 2초 멈췄을 때, 대화를 마칠 때.
    private func finalizeTurn(endMs: Int?, requestDecision: Bool = true) {
        turnTimer?.cancel(); turnTimer = nil
        guard !openTurn.isEmpty else { return }
        let parts = openTurn.sorted { $0.start < $1.start }
        openTurn = []
        let text = String(parts.map(\.text).joined().suffix(1600))
        // 서버 규칙: 발화 글자는 공백 불가, end_ms ≥ start_ms ≥ 0
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let startMs = max(0, parts.first?.start ?? 0)
        let endMs = max(startMs, endMs ?? parts.last?.start ?? startMs)
        turnSeq += 1
        let uid = "u_\(String(format: "%04d", turnSeq))"
        transcriptLog.append(.init(direction: "input", utteranceId: uid, text: text, startMs: startMs, endMs: endMs))
        if requestDecision {
            queue?.pushFinal(input: inputText(), output: outputText(),
                             utterance: .init(text: text, startMs: startMs, endMs: endMs), utteranceId: uid)
            if Self.soundsLikeFarewell(text) { requestEnd() }
        }
    }
    private func inputText() -> String { String(inputParts.map(\.text).joined().suffix(1600)) }
    private func outputText() -> String { String(outputParts.map(\.text).joined().suffix(800)) }
    private func currentTranscript() -> [TranscriptPart] { transcriptLog }

    // MARK: - 비용 표시(PoC metrics)

    var voiceCostText: String {
        guard let s = usageSeconds else { return "연결 전" }
        return String(format: "$%.4f", s / 60 * ConfigStore.shared.current.pricing.livePerMinUsd)
    }
    var decisionCostText: String {
        String(format: "$%.6f", Double(stats.inputTokens) * ConfigStore.shared.current.pricing.decisionPerMtokUsd / 1_000_000)
            + (stats.unknown > 0 ? " + 미확인" : "")
    }
    var totalCostText: String {
        guard let s = usageSeconds else { return "연결 전" }
        let p = ConfigStore.shared.current.pricing
        return String(format: "$%.4f", s / 60 * p.livePerMinUsd + Double(stats.inputTokens) * p.decisionPerMtokUsd / 1_000_000)
    }
}
