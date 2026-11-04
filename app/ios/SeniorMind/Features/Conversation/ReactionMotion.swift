import Foundation

/// 서버 `reaction` 6종 → 표정 4종(앱 계획서 1.4 매핑 표).
/// 같은 반응 반복은 무시하고, 놀람은 1,040ms 뒤 기쁨(surprised_happy) 또는 공감(surprised_concern)으로 넘어간다.
/// 날개·몸 동작은 표정이 정하므로 여기서는 표정만 바꾼다.
@MainActor
final class ReactionMotion {
    private let bird: BirdModel
    private var last: Reaction = .neutral
    private var face: Expression = .neutral
    private var task: Task<Void, Never>?
    /// 안전 문구가 나가는 동안 공감 표정 고정(safety_override)
    private(set) var locked = false
    var onFace: (Expression) -> Void = { _ in }

    init(bird: BirdModel) { self.bird = bird }

    private func show(_ e: Expression, intensity: Double = 1) {
        guard e != face else { return }
        face = e
        bird.setExpression(e, intensity: intensity)
        onFace(e)
    }

    @discardableResult
    func accept(_ reaction: Reaction) -> Bool {
        guard !locked, reaction != .hold, reaction != last else { return false }
        last = reaction
        task?.cancel()
        switch reaction {
        case .surprisedHappy, .surprisedConcern:
            show(.surprised, intensity: 0.65)
            task = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1040))
                guard !Task.isCancelled else { return }
                self?.show(reaction == .surprisedConcern ? .empathy : .happy)
            }
        case .happy: show(.happy)
        case .empathy: show(.empathy)
        case .neutral: show(.neutral)
        case .hold: break
        }
        return true
    }

    /// 서버가 safety_override=true를 보내면 공감으로 고정하고 자동 전환을 멈춘다.
    func lockEmpathy() {
        task?.cancel(); last = .empathy; show(.empathy); locked = true
    }
    func unlock() { locked = false }

    func reset() { task?.cancel(); locked = false; last = .neutral; face = .neutral; bird.setExpression(.neutral); onFace(.neutral) }
    func stop() { task?.cancel() }
}
