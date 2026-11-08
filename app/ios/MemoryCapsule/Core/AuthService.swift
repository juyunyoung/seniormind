import Foundation
#if canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseCore
#endif

/// 로그인. 어르신은 익명, 보호자는 이메일·비밀번호(팀 서버 Firebase에 켜진 방식). Google·Apple은 나중에.
protocol AuthService: Sendable {
    func signInSenior() async throws -> String
    func idToken() async throws -> String
    /// G01 보호자 로그인
    func signInGuardian(email: String, password: String) async throws -> String
    /// G29 보호자 회원가입
    func signUpGuardian(email: String, password: String) async throws -> String
    /// G30 비밀번호 찾기(가입 여부와 관계없이 같은 안내를 보여 준다)
    func sendPasswordReset(email: String) async throws
    func signOut() throws
    /// 이미 로그인된 보호자(익명이 아닌) 계정이 있는지
    var hasGuardianSession: Bool { get }
}

enum AuthError: Error, LocalizedError {
    case invalidCredentials, weakPassword, emailInUse, network
    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "로그인하지 못했어요. 이메일·비밀번호 또는 연결 상태를 확인해 주세요."
        case .weakPassword: "비밀번호는 6자 이상으로 정해 주세요."
        case .emailInUse: "이미 가입된 이메일이에요. 로그인해 주세요."
        case .network: "지금은 연결이 어려워요. 잠시 후 다시 해 주세요."
        }
    }
}

/// 목 모드용. 비밀번호가 "wrong"이면 로그인 실패(G02 화면 확인용).
final class MockAuthService: AuthService, @unchecked Sendable {
    private let lock = NSLock()
    private var guardian = UserDefaults.standard.bool(forKey: "mc.mock.guardian_session")

    func signInSenior() async throws -> String { "mock-senior" }
    func idToken() async throws -> String { "mock-token" }
    func signInGuardian(email: String, password: String) async throws -> String {
        try await Task.sleep(for: .milliseconds(400))
        guard email.contains("@"), password != "wrong" else { throw AuthError.invalidCredentials }
        setGuardian(true); return "mock-guardian"
    }
    func signUpGuardian(email: String, password: String) async throws -> String {
        try await Task.sleep(for: .milliseconds(400))
        guard password.count >= 6 else { throw AuthError.weakPassword }
        setGuardian(true); return "mock-guardian"
    }
    func sendPasswordReset(email: String) async throws { try await Task.sleep(for: .milliseconds(300)) }
    func signOut() throws { setGuardian(false) }
    var hasGuardianSession: Bool { lock.withLock { guardian } }
    private func setGuardian(_ v: Bool) {
        lock.withLock { guardian = v }
        UserDefaults.standard.set(v, forKey: "mc.mock.guardian_session")
    }
}

#if canImport(FirebaseAuth)
/// 익명 로그인을 한 번만 진행한다. 앱 시작·동의 저장·서버 호출이 동시에 부르면 같은 결과를 기다린다
/// (동시에 두 번 부르면 익명 계정이 두 개 생겨 동의와 세션이 다른 계정에 기록되는 문제가 있었음).
@MainActor
enum AnonymousSignIn {
    private static var task: Task<String, Error>?
    static func run() async throws -> String {
        if let user = Auth.auth().currentUser { return user.uid }
        if let task { return try await task.value }
        let t = Task { try await Auth.auth().signInAnonymously().user.uid }
        task = t
        defer { task = nil }
        return try await t.value
    }
}

/// Firebase 로그인. 어르신은 익명(backend 1.0), 보호자는 이메일·비밀번호.
struct FirebaseAuthService: AuthService {
    static var isConfigured: Bool { FirebaseApp.app() != nil }

    func signInSenior() async throws -> String { try await AnonymousSignIn.run() }
    func idToken() async throws -> String {
        var user = Auth.auth().currentUser
        // 앱 시작 때 익명 로그인이 실패했으면(네트워크·콘솔 설정) 어르신은 여기서 다시 시도한다
        if user == nil, UserDefaults.standard.string(forKey: "mc.role") == UserRole.senior.rawValue {
            do { _ = try await AnonymousSignIn.run(); user = Auth.auth().currentUser }
            catch {
                #if DEBUG
                print("[MC] 익명 로그인 실패: \(error)")
                #endif
                throw APIError.server(status: 0, code: "auth_failed", message: "로그인하지 못했어요. Firebase 익명 로그인 설정을 확인해 주세요.")
            }
        }
        guard let user else { throw APIError.notConfigured }
        return try await user.getIDToken()
    }
    func signInGuardian(email: String, password: String) async throws -> String {
        do { return try await Auth.auth().signIn(withEmail: email, password: password).user.uid }
        catch { throw map(error) }
    }
    func signUpGuardian(email: String, password: String) async throws -> String {
        do { return try await Auth.auth().createUser(withEmail: email, password: password).user.uid }
        catch { throw map(error) }
    }
    func sendPasswordReset(email: String) async throws {
        try? await Auth.auth().sendPasswordReset(withEmail: email)   // 가입 여부를 알려 주지 않는다
    }
    func signOut() throws { try Auth.auth().signOut() }
    var hasGuardianSession: Bool {
        guard let u = Auth.auth().currentUser else { return false }
        return !u.isAnonymous
    }
    private func map(_ error: Error) -> AuthError {
        switch AuthErrorCode(rawValue: (error as NSError).code) {
        case .weakPassword: .weakPassword
        case .emailAlreadyInUse: .emailInUse
        case .networkError: .network
        default: .invalidCredentials
        }
    }
}
#endif
