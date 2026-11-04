import Foundation
#if canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseCore
#endif

protocol AuthService: Sendable {
    func signInSenior() async throws -> String
    func idToken() async throws -> String
}

/// 목 모드용.
struct MockAuthService: AuthService {
    func signInSenior() async throws -> String { "mock-senior" }
    func idToken() async throws -> String { "mock-token" }
}

#if canImport(FirebaseAuth)
/// 어르신은 익명 인증(backend 1.0). 보호자 이메일·Google·Apple 로그인은 GuardianSignInView에서 FirebaseAuth로 처리.
struct FirebaseAuthService: AuthService {
    static var isConfigured: Bool { FirebaseApp.app() != nil }

    func signInSenior() async throws -> String {
        if let user = Auth.auth().currentUser { return user.uid }
        return try await Auth.auth().signInAnonymously().user.uid
    }
    func idToken() async throws -> String {
        guard let user = Auth.auth().currentUser else { throw APIError.notConfigured }
        return try await user.getIDToken()
    }
}
#endif
