import SwiftUI
import VisionKit

/// 부모님 연결: G03 방법 고르기 → G22 QR 읽기 / G23 인증번호(G26 오류) → G24 확인(guardian_data_view 동의 + 연결).
/// 어르신 승인 화면은 없다(P04·G25 만들지 않음). QR을 읽으면 바로 연결 요청.
enum LinkRoute: Hashable {
    case qr, code
    case confirm(code: String, seniorId: String, name: String?)
}

/// QR·번호 → 부모님 확인. 서버 N21 `POST /pairing/resolve`(팀 서버 미구현, 목 모드만 동작).
enum PairingResolver {
    static let errorText = "번호가 맞지 않거나 만료됐어요. 부모님 앱의 새 번호를 확인해 주세요."
    static func resolve(_ code: String, api: APIClient) async -> Result<LinkRoute, PairingResolveError> {
        do {
            let t = try await api.resolvePairing(code: code)
            return .success(.confirm(code: code, seniorId: t.seniorId, name: t.displayName))
        } catch let e as APIError where e.status == 404 || e.status == 405 {
            return .failure(.init(message: "아직 서버가 준비되지 않았어요. (pairing/resolve)"))
        } catch {
            return .failure(.init(message: errorText))
        }
    }
}
struct PairingResolveError: Error { let message: String }

struct GuardianLinkFlow: View {
    @Environment(AppState.self) private var app
    @Environment(GuardianStore.self) private var store
    @State private var path: [LinkRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            GuardianScaffold(title: "부모님 연결") {
                SpeechBubble(text: "부모님 앱에서\n보호자 연결을 열어 주세요.", size: 24)
                SmallBird(size: 120).frame(maxWidth: .infinity)
                NavigationLink(value: LinkRoute.qr) { GuardianRowLabel(title: "QR코드 읽기", detail: "부모님 화면의 QR을 카메라로 읽어요") }
                    .buttonStyle(.plain)
                NavigationLink(value: LinkRoute.code) { GuardianRowLabel(title: "인증번호 입력", detail: "부모님 화면의 6자리 번호를 입력해요") }
                    .buttonStyle(.plain)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("로그아웃") { try? app.auth.signOut(); store.signedOut() }
                }
            }
            .navigationDestination(for: LinkRoute.self) { r in
                switch r {
                case .qr: GuardianQRView(path: $path)
                case .code: GuardianCodeView(path: $path)
                case .confirm(let code, let seniorId, let name):
                    GuardianLinkConfirmView(code: code, seniorId: seniorId, name: name, path: $path)
                }
            }
            .task {
                // 카메라 앱으로 QR을 읽어 딥링크로 들어온 경우
                if let code = DeepLink.pendingPairCode {
                    DeepLink.pendingPairCode = nil
                    if case .success(let r) = await PairingResolver.resolve(code, api: app.api) { path = [r] }
                    else { path = [.code] }
                }
            }
        }
        .tint(Theme.green)
    }
}

/// G22 · QR 읽기
struct GuardianQRView: View {
    @Binding var path: [LinkRoute]
    @Environment(AppState.self) private var app
    @State private var error: String?
    @State private var busy = false
    private let canScan = DataScannerViewController.isSupported && DataScannerViewController.isAvailable

    var body: some View {
        GuardianScaffold(title: "QR코드 읽기") {
            Text("부모님 화면의 QR을\n이 안에 맞춰 주세요").font(.system(size: 22, weight: .bold)).frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            ZStack {
                if canScan {
                    QRScannerView { text in
                        guard !busy, let code = DeepLink.parsePairCode(text) else { return }
                        Task { await resolve(code) }
                    }
                } else {
                    Theme.secondaryFill
                    Text("이 기기에서는 카메라로 읽을 수 없어요.\n인증번호로 입력해 주세요.").font(.system(size: 17))
                        .foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding()
                }
                if busy { ProgressView().controlSize(.large) }
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.selectedBorder, lineWidth: 3))
            .accessibilityLabel("QR 읽는 칸")
            if let error { GuardianErrorText(text: error) }
        } bottom: {
            if AppInfo.useMock {
                Button("목: QR 읽은 것으로 하기") { Task { await resolve("123456") } }.buttonStyle(SecondaryButtonStyle())
            }
            Button("인증번호로 입력하기") { path = [.code] }.buttonStyle(SecondaryButtonStyle())
        }
    }

    private func resolve(_ code: String) async {
        busy = true; error = nil; defer { busy = false }
        switch await PairingResolver.resolve(code, api: app.api) {
        case .success(let r): path.append(r)
        case .failure(let e): error = e.message
        }
    }
}

/// G23 · 인증번호 입력 (G26 오류)
struct GuardianCodeView: View {
    @Binding var path: [LinkRoute]
    @Environment(AppState.self) private var app
    @State private var code = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        GuardianScaffold(title: "인증번호 입력") {
            Text("부모님 화면에 보이는\n6자리 번호를 입력해 주세요.").font(.system(size: 22, weight: .bold))
            GuardianField("인증번호", text: $code, kind: .code, placeholder: "000000")
                .onChange(of: code) { _, v in
                    let digits = String(v.filter(\.isNumber).prefix(6))
                    if digits != v { code = digits }
                    error = nil
                }
            if let error { GuardianErrorText(text: error) }   // G26
            if AppInfo.useMock { Text("목 모드: 아무 6자리는 성공, 000000은 만료").font(.footnote).foregroundStyle(Theme.muted) }
        } bottom: {
            Button(busy ? "확인 중…" : "부모님 확인하기") { Task { await resolve() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(code.count != 6 || busy)
            if error != nil {
                Button("QR코드로 연결하기") { path = [.qr] }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func resolve() async {
        busy = true; defer { busy = false }
        switch await PairingResolver.resolve(code, api: app.api) {
        case .success(let r): path.append(r)
        case .failure(let e): error = e.message
        }
    }
}

/// G24 · 연결할 부모님 확인. 여기서 guardian_data_view 동의를 기록하고(linked_senior_id 필수) 연결한다.
struct GuardianLinkConfirmView: View {
    let code: String
    let seniorId: String
    let name: String?
    @Binding var path: [LinkRoute]
    @Environment(AppState.self) private var app
    @Environment(GuardianStore.self) private var store
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        GuardianScaffold(title: "연결 확인") {
            GuardianCard(title: "연결할 부모님") {
                Text("\(name ?? "부모님")님").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.green)
            }
            GuardianCard(title: "함께 살펴볼 정보") {
                Text("대화 기록, 마음의 변화와\n확인이 필요한 신호").font(.system(size: 19, weight: .semibold)).lineSpacing(3)
                Text("대화 원문과 음성은 보이지 않아요.").font(.system(size: 16)).foregroundStyle(Theme.muted)
            }
            Text("연결 요청하기를 누르면 위 정보를 보는 데 동의한 것으로 기록돼요.")
                .font(.system(size: 15)).foregroundStyle(Theme.muted)
            if let error { GuardianErrorText(text: error) }
        } bottom: {
            Button(busy ? "연결 중…" : "연결 요청하기") { Task { await link() } }
                .buttonStyle(PrimaryButtonStyle()).disabled(busy)
            Button("다시 확인하기") { path.removeAll() }.buttonStyle(SecondaryButtonStyle())
        }
    }

    private func link() async {
        busy = true; error = nil; defer { busy = false }
        do {
            try await app.api.postConsent(.init(type: .guardianDataView, version: ConsentStep.version, granted: true,
                                                method: "screen_tap", linkedSeniorId: seniorId))
            _ = try await app.api.link(code: code, relation: "가족")
            await store.loadLinks(app.api)      // 연결되면 탭 화면으로 바뀐다
        } catch let e as APIError where e.code == "already_linked" {
            await store.loadLinks(app.api)
            error = "이미 연결된 부모님이에요."
        } catch let e as APIError where e.code == "pairing_code_expired" || e.code == "pairing_code_invalid" {
            error = PairingResolver.errorText
        } catch {
            self.error = "지금은 연결이 어려워요. 잠시 후 다시 해 주세요."
        }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                                           isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in items { if case .barcode(let b) = item, let v = b.payloadStringValue { onCode(v); return } }
        }
    }
}
