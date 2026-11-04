import Foundation

/// PoC reactions.mjs `DecisionQueue` + 최종 판단(final) 보장(app_spec 1.3).
/// - 중간 판단: batchMs 단위로 묶고, 판단 중이면 최신 텍스트로 합친다. 실패는 다음 묶음에서.
/// - 최종 판단: 턴 종료마다 반드시 1회. 실패 시 1·2·4초 재시도(같은 utterance_id → 서버 멱등).
@MainActor
final class DecisionQueue {
    struct Stats { var requested = 0, completed = 0, applied = 0, merged = 0, errors = 0, inputTokens = 0, unknown = 0; var pending = false; var latencyMs: Int? }

    private let api: APIClient
    private let sessionId: String
    private let interval: Duration
    private let onResult: (DecisionResponse, _ final: Bool, _ utteranceId: String) -> Void
    private let onStats: (Stats) -> Void

    private(set) var stats = Stats() { didSet { onStats(stats) } }
    private var previous: Reaction = .neutral
    private var pending: (text: String, output: String, at: ContinuousClock.Instant)?
    private var lastText = ""
    private var lastSent = ContinuousClock.now - .seconds(60)
    private var busy = false
    private var timer: Task<Void, Never>?
    private var closed = false
    private var seq = 0

    init(api: APIClient, sessionId: String, batchMs: Int,
         onResult: @escaping (DecisionResponse, Bool, String) -> Void, onStats: @escaping (Stats) -> Void) {
        self.api = api; self.sessionId = sessionId; self.interval = .milliseconds(batchMs)
        self.onResult = onResult; self.onStats = onStats
    }

    /// 입력 자막이 늘어날 때(중간 판단)
    func push(input: String, output: String) {
        guard !closed, !input.trimmingCharacters(in: .whitespaces).isEmpty, input != lastText, input != pending?.text else { return }
        if pending != nil { pending?.text = input; pending?.output = output; stats.merged += 1 }
        else { pending = (input, output, .now) }
        schedule()
    }

    private func schedule() {
        guard !closed, !busy, timer == nil, let pending else { return }
        let now = ContinuousClock.now
        let delay = max(.zero, max(lastSent + interval - now, pending.at + interval - now))
        timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            self.timer = nil
            await self.runIntermediate()
        }
    }

    private func runIntermediate() async {
        guard !closed, !busy, let item = pending else { return }
        pending = nil; lastText = item.text; lastSent = .now; busy = true
        stats.requested += 1; stats.pending = true
        seq += 1
        let request = DecisionRequest(sessionId: sessionId, utteranceId: "u_\(seq)_mid", inputText: String(item.text.suffix(1600)),
                                      outputText: String(item.output.suffix(800)), previousReaction: previous, final: false, utterance: nil)
        do {
            let r = try await api.decision(request)
            record(r, startedAt: item.at)
            if !closed { onResult(r, false, request.utteranceId) }
        } catch { stats.errors += 1 }
        busy = false; stats.pending = false
        schedule()
    }

    /// 턴 종료(입력 자막 완료) 시 호출. 반드시 전송.
    func pushFinal(input: String, output: String, utterance: Utterance, utteranceId: String) {
        guard !closed else { return }
        let request = DecisionRequest(sessionId: sessionId, utteranceId: utteranceId, inputText: String(input.suffix(1600)),
                                      outputText: String(output.suffix(800)), previousReaction: previous, final: true, utterance: utterance)
        let started = ContinuousClock.now
        Task { [weak self] in
            for (attempt, wait) in [0, 1, 2, 4].enumerated() {
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard let self else { return }
                self.stats.requested += 1
                do {
                    let r = try await self.api.decision(request)
                    self.record(r, startedAt: started)
                    self.onResult(r, true, utteranceId)
                    return
                } catch {
                    self.stats.errors += 1
                    if attempt == 3 { return }
                }
            }
        }
    }

    private func record(_ r: DecisionResponse, startedAt: ContinuousClock.Instant) {
        stats.completed += 1
        stats.latencyMs = Int((ContinuousClock.now - startedAt) / .milliseconds(1))
        if let t = r.usage?.inputTokens { stats.inputTokens += t } else { stats.unknown += 1 }
        if r.reaction != .hold { previous = r.reaction }
    }

    func countApplied() { stats.applied += 1 }
    func stop() { closed = true; timer?.cancel(); timer = nil; pending = nil }
}
