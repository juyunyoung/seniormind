import Foundation

/// 서버 설정(`GET /config/latest`) 보관. P1은 서명 없이 저장, 실패하면 이전 저장본 → 앱 내장 기본값.
/// P2: CryptoKit P256 공개키로 서명 검증(backend 1.6, iOS 대응표 1.8).
final class ConfigStore: @unchecked Sendable {
    static let shared = ConfigStore()
    private let key = "mc.config.v1"
    private let lock = NSLock()
    private var cached: AppConfig?

    var current: AppConfig {
        lock.withLock {
            if let cached { return cached }
            if let data = UserDefaults.standard.data(forKey: key),
               let saved = try? JSONDecoder().decode(AppConfig.self, from: data) {
                cached = saved; return saved
            }
            return .builtIn
        }
    }

    func refresh(using api: APIClient) async {
        guard let response = try? await api.config() else { return }
        // TODO(P2): response.signature 검증 실패 시 return
        lock.withLock {
            cached = response.config
            if let data = try? JSONEncoder().encode(response.config) { UserDefaults.standard.set(data, forKey: key) }
        }
    }

    /// 서버가 준 ID 우선, 없으면 등급 기본 문구(R2: R2_CHECK_IN, R3: R3_SAFETY_CHECK).
    func safetyPhrase(id: String?, level: RiskLevel) -> SafetyPhrase? {
        let phrases = current.safety.phrases
        if let id, let p = phrases.first(where: { $0.id == id }) { return p }
        let fallback = level == .r2 ? "R2_CHECK_IN" : "R3_SAFETY_CHECK"
        return phrases.first { $0.id == fallback } ?? phrases.first { $0.level == level }
    }
    func actionText(code: String?) -> String? { code.flatMap { current.safety.actionText?[$0] } }
}
