import Foundation
#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
import FirebaseCore
#endif

/// PC·스크립트에서 서버 API를 직접 부르는 것을 막기 위한 Firebase App Check.
/// - 유료 계정 전환 후: App Attest(진짜 기기의 진짜 앱인지 Apple이 증명)
/// - 무료 계정·시뮬레이터: 디버그 공급자(콘솔에 디버그 토큰 등록 필요)
/// 서버가 X-Firebase-AppCheck 헤더를 검증한다. 팀 백엔드는 아직 검증하지 않으며(헤더는 무시됨), 출시 전 적용 예정.
protocol AppCheckService: Sendable {
    func token() async -> String?
}

struct NoAppCheck: AppCheckService {
    func token() async -> String? { nil }
}

#if canImport(FirebaseAppCheck)
final class MemoryCapsuleAppCheckFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if DEBUG
        return AppCheckDebugProvider(app: app)
        #else
        return AppAttestProvider(app: app)
        #endif
    }
}

struct FirebaseAppCheckService: AppCheckService {
    /// FirebaseApp.configure() 전에 한 번 호출.
    static func install() { AppCheck.setAppCheckProviderFactory(MemoryCapsuleAppCheckFactory()) }

    func token() async -> String? {
        try? await AppCheck.appCheck().token(forcingRefresh: false).token
    }
}
#endif
