import SwiftUI
import Observation
import CoreImage.CIFilterBuiltins

// MARK: - S08 말로 조작하기

/// S08 · 무엇을 도와드릴까요? — 말하는 속도, "보호자 연결해줘", 홈으로 가기.
/// 동의 철회·연결 끊기는 와이어프레임에 없지만 개인정보 철회 수단이라 마지막 줄에 둔다.
struct SeniorSettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(SeniorRouter.self) private var router

    var body: some View {
        SeniorScaffold(onBack: { router.pop() }) {
            SpeechBubble(text: "무엇을 도와드릴까요?")
            SmallBird(size: 130).padding(.top, 14)
            VStack(spacing: 12) {
                SeniorMenuRow(title: "말하는 속도 · \(app.speechRate == "slow" ? "천천히" : "보통")", trailing: nil) { router.push(.speed) }
                SeniorMenuRow(title: "“보호자 연결해줘”", trailing: nil) { startPairing() }
                SeniorMenuRow(title: "연결된 보호자 · 동의 관리", trailing: "›") { router.push(.manage) }
            }
            .padding(.top, 18)
        } bottom: {
            Button("홈으로 가기") { router.home() }.buttonStyle(SecondaryButtonStyle())
        }
        .onAppear { Narrator.shared.say("무엇을 도와드릴까요?") }
    }

    private func startPairing() {
        // 서버가 연결 코드 발급 전에 확인하는 동의(보호자 공유·일정 공유). 없으면 동의 화면을 먼저.
        let d = UserDefaults.standard
        let ok = d.bool(forKey: "mc.consent.guardian_share") && d.bool(forKey: "mc.consent.schedule_share")
        router.push(ok ? .pairMenu : .pairConsent)
    }
}

// MARK: - S13 말하는 속도

struct SpeechRateView: View {
    @Environment(AppState.self) private var app
    @Environment(SeniorRouter.self) private var router

    var body: some View {
        SeniorScaffold(onBack: { router.pop() }) {
            SpeechBubble(text: "말하는 속도를\n골라 주세요.")
            SmallBird(size: 130).padding(.top, 14)
            VStack(spacing: 12) {
                option("천천히", value: "slow")
                option("보통", value: "normal")
            }
            .padding(.top, 18)
        } bottom: {
            Button("홈으로 가기") { router.home() }.buttonStyle(SecondaryButtonStyle())
        }
        .onAppear { Narrator.shared.say("말하는 속도를 골라 주세요.") }
    }

    private func option(_ title: String, value: String) -> some View {
        let selected = app.speechRate == value
        return SeniorMenuRow(title: selected ? "\(title) ✓" : title, trailing: nil, selected: selected) {
            Task { await app.setSpeechRate(value); Narrator.shared.say("\(title)으로 말할게요.") }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - 연결된 보호자 · 동의 관리 (와이어프레임 없음)

struct SeniorManageView: View {
    @Environment(AppState.self) private var app
    @Environment(SeniorRouter.self) private var router
    @State private var links: [GuardianLink] = []
    @State private var unlinkTarget: GuardianLink?
    @State private var consents: [ConsentType: Bool] = [:]

    private struct ConsentRow: Identifiable { let type: ConsentType; let title: String; var id: String { type.rawValue } }
    private let rows: [ConsentRow] = [
        .init(type: .voiceTransfer, title: "목소리 전송"), .init(type: .transcriptStore, title: "대화 내용 보관"),
        .init(type: .memoryCard, title: "기억 카드"), .init(type: .sensitive, title: "힘든 신호 알림"),
        .init(type: .guardianShare, title: "보호자에게 요약 보이기"), .init(type: .scheduleShare, title: "약·일정 함께 챙기기"),
        .init(type: .guardianTopicShare, title: "이야기 나눈 주제 보이기"),
    ]

    var body: some View {
        SeniorScaffold(onBack: { router.pop() }) {
            VStack(alignment: .leading, spacing: 14) {
                Text("연결된 보호자").font(.system(size: 22, weight: .bold))
                if links.isEmpty { Text("아직 연결된 보호자가 없어요.").font(.system(size: 19)).foregroundStyle(Theme.muted) }
                ForEach(links) { link in
                    SeniorCard {
                        Text(link.displayName ?? link.relation ?? "보호자").font(.system(size: 22, weight: .bold))
                        Button("연결 끊기", role: .destructive) { unlinkTarget = link }.font(.system(size: 19, weight: .semibold))
                    }
                }
                Text("동의 확인·철회").font(.system(size: 22, weight: .bold)).padding(.top, 10)
                ForEach(rows) { row in
                    Toggle(row.title, isOn: Binding(get: { consents[row.type] ?? false }, set: { set(row.type, $0) }))
                        .font(.system(size: 20)).frame(minHeight: 52)
                }
                Text("목소리 전송과 대화 내용 보관을 끄면 기억이와 대화할 수 없어요.")
                    .font(.system(size: 17)).foregroundStyle(Theme.muted)
                Button("알람 권한 확인") { Task { _ = await AlarmScheduler.shared.requestPermission() } }
                    .font(.system(size: 19, weight: .semibold)).padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } bottom: {
            Button("홈으로 가기") { router.home() }.buttonStyle(SecondaryButtonStyle())
        }
        .task { load(); await reload() }
        .confirmationDialog("보호자 연결을 끊을까요?", isPresented: Binding(get: { unlinkTarget != nil }, set: { if !$0 { unlinkTarget = nil } }),
                            titleVisibility: .visible) {
            Button("연결 끊기", role: .destructive) {
                if let t = unlinkTarget { Task { try? await app.api.unlink(linkId: t.linkId); await reload() } }
            }
        }
    }

    private func reload() async {
        links = (try? await app.api.links()) ?? []
        app.hasGuardian = !links.isEmpty
    }
    private func load() {
        for row in rows { consents[row.type] = UserDefaults.standard.bool(forKey: "mc.consent.\(row.type.rawValue)") }
    }
    private func set(_ type: ConsentType, _ granted: Bool) {
        consents[type] = granted
        UserDefaults.standard.set(granted, forKey: "mc.consent.\(type.rawValue)")
        Task { try? await app.api.postConsent(.init(type: type, version: ConsentStep.version, granted: granted,
                                                    method: "screen_tap", linkedSeniorId: nil)) }
    }
}

// MARK: - 보호자 연결 (P01·P02·P03·P05·P06)

/// 연결 코드 1회분. QR과 6자리 번호는 같은 코드(서버 qr_payload). 연결되면 P05, 만료되면 P06.
@Observable @MainActor
final class PairingSession {
    var pairing: PairingCode?
    var error: String?
    var linked = false
    @ObservationIgnored private var watcher: Task<Void, Never>?

    var expired: Bool { pairing.map { $0.expiresAt <= .now } ?? false }

    func ensureCode(api: APIClient) async {
        if pairing == nil || expired { await renew(api: api) }
    }

    func renew(api: APIClient) async {
        do { pairing = try await api.pairingCode(); error = nil }
        catch let e as APIError where e.code == "consent_required" { error = "먼저 보호자 공유 동의가 필요해요." }
        catch { self.error = "지금은 연결이 어려워요. 잠시 후 다시 해 주세요." }
    }

    /// P02·P03에 있는 동안: 5초마다 연결 확인(푸시 pairing_done은 보조), 만료 확인.
    func watch(api: APIClient, router: SeniorRouter, onLinked: @escaping () -> Void) {
        watcher?.cancel()
        watcher = Task { [weak self] in
            let before = (try? await api.links().count) ?? 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                if let now = try? await api.links().count, now > before { self.finish(router: router, onLinked: onLinked); return }
                if self.expired { router.replace(.pairExpired); return }
            }
        }
    }

    func finish(router: SeniorRouter, onLinked: () -> Void) {
        watcher?.cancel()
        linked = true
        pairing = nil
        onLinked()
        router.replace(.pairDone)
    }

    func stop() { watcher?.cancel() }
}

/// P01 · 보호자 휴대폰에서 이 QR이나 번호를 확인해요.
struct PairMenuView: View {
    @Environment(AppState.self) private var app
    @Environment(SeniorRouter.self) private var router
    @Environment(PairingSession.self) private var pairing

    var body: some View {
        SeniorScaffold(onBack: { router.pop() }) {
            SpeechBubble(text: "보호자 휴대폰에서\n이 QR이나 번호를\n확인해요.")
            SmallBird(size: 120).padding(.top, 14)
            VStack(spacing: 12) {
                SeniorMenuRow(title: "QR코드 보여주기", detail: "보호자가 카메라로 읽어요") { router.push(.pairQR) }
                SeniorMenuRow(title: "인증번호 보여주기", detail: "보호자가 번호를 입력해요") { router.push(.pairCode) }
            }
            .padding(.top, 18)
            if let e = pairing.error { Text(e).font(.system(size: 18)).foregroundStyle(Theme.error).padding(.top, 12) }
        } bottom: {
            Button("홈으로 가기") { router.home() }.buttonStyle(SecondaryButtonStyle())
        }
        .task { await pairing.ensureCode(api: app.api) }
        .onAppear { Narrator.shared.say("보호자 휴대폰에서 이 QR이나 번호를 확인해요.") }
    }
}

/// P02 · 보호자 휴대폰으로 이 QR을 읽어 주세요.
struct PairQRView: View {
    @Environment(AppState.self) private var app
    @Environment(SeniorRouter.self) private var router
    @Environment(PairingSession.self) private var pairing

    var body: some View {
        SeniorScaffold(onBack: { pairing.stop(); router.pop() }) {
            SpeechBubble(text: "보호자 휴대폰으로\n이 QR을 읽어 주세요.")
            Group {
                if let p = pairing.pairing, let image = qrImage(p.qrPayload) {
                    Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                        .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.cardBorder))
                        .accessibilityLabel("보호자 연결 QR 코드")
                } else if let e = pairing.error {
                    Text(e).font(.system(size: 19)).foregroundStyle(Theme.error)
                } else { ProgressView().frame(height: 260) }
            }
            .frame(maxWidth: 300).padding(.top, 28)
        } bottom: {
            Button("인증번호 보여줘") { router.replace(.pairCode) }.buttonStyle(SecondaryButtonStyle())
        }
        .task {
            await pairing.ensureCode(api: app.api)
            pairing.watch(api: app.api, router: router) { app.hasGuardian = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pairingDone)) { _ in pairing.finish(router: router) { app.hasGuardian = true } }
        .onAppear { Narrator.shared.say("보호자 휴대폰으로 이 QR을 읽어 주세요.") }
    }
}

/// P03 · 보호자 휴대폰에 이 번호를 입력해 주세요. (QR이 어려울 때의 대체 수단)
struct PairCodeView: View {
    @Environment(AppState.self) private var app
    @Environment(SeniorRouter.self) private var router
    @Environment(PairingSession.self) private var pairing

    var body: some View {
        SeniorScaffold(onBack: { pairing.stop(); router.pop() }) {
            SpeechBubble(text: "보호자 휴대폰에\n이 번호를 입력해 주세요.")
            SmallBird(size: 110).padding(.top, 14)
            SeniorCard {
                Text("보호자 연결 인증번호").font(.system(size: 19, weight: .semibold))
                    .frame(maxWidth: .infinity)
                Text(spaced(pairing.pairing?.code))
                    .font(.system(size: 44, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("인증번호 \(pairing.pairing?.code.map { String($0) }.joined(separator: " ") ?? "")")
            }
            .padding(.top, 18)
            if let e = pairing.error { Text(e).font(.system(size: 18)).foregroundStyle(Theme.error).padding(.top, 12) }
        } bottom: {
            Button("QR 보여줘") { router.replace(.pairQR) }.buttonStyle(SecondaryButtonStyle())
            Button("홈으로 가기") { pairing.stop(); router.home() }.buttonStyle(SecondaryButtonStyle())
        }
        .task {
            await pairing.ensureCode(api: app.api)
            pairing.watch(api: app.api, router: router) { app.hasGuardian = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pairingDone)) { _ in pairing.finish(router: router) { app.hasGuardian = true } }
        .onAppear {
            let code = pairing.pairing?.code.map { String($0) }.joined(separator: " ") ?? ""
            Narrator.shared.say("보호자 휴대폰에 이 번호를 입력해 주세요. \(code)")
        }
    }

    private func spaced(_ code: String?) -> String {
        guard let code, code.count == 6 else { return "— — —" }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }
}

/// P05 · 보호자와 연결됐어요.
struct PairDoneView: View {
    @Environment(SeniorRouter.self) private var router
    @State private var bird = BirdModel()

    var body: some View {
        SeniorScaffold {
            SpeechBubble(text: "이제 가족과 함께\n안부를 살펴볼 수\n있어요.")
            BirdView(model: bird).frame(width: 150, height: 150).padding(.top, 18).accessibilityHidden(true)
        } bottom: {
            Button("기억이와 이야기하기") { router.home() }.buttonStyle(PrimaryButtonStyle())
        }
        .onAppear { bird.setExpression(.happy); Narrator.shared.say("보호자와 연결됐어요. 이제 가족과 함께 안부를 살펴볼 수 있어요.") }
    }
}

/// P06 · 새 번호를 보여드릴게요. (코드 5분 만료)
struct PairExpiredView: View {
    @Environment(AppState.self) private var app
    @Environment(SeniorRouter.self) private var router
    @Environment(PairingSession.self) private var pairing

    var body: some View {
        SeniorScaffold(onBack: { router.pop() }) {
            SpeechBubble(text: "새 번호를\n보여드릴게요.\n보호자에게 새 QR이나\n인증번호를 보여\n주세요.")
            SmallBird(size: 130).padding(.top, 14)
        } bottom: {
            Button("새 번호 보여줘") { Task { await pairing.renew(api: app.api); router.replace(.pairCode) } }
                .buttonStyle(PrimaryButtonStyle())
            Button("QR 보여줘") { Task { await pairing.renew(api: app.api); router.replace(.pairQR) } }
                .buttonStyle(SecondaryButtonStyle())
        }
        .onAppear { Narrator.shared.say("시간이 지나 새 번호를 보여드릴게요.") }
    }
}

func qrImage(_ text: String) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let out = filter.outputImage?.transformed(by: .init(scaleX: 10, y: 10)),
          let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
    return UIImage(cgImage: cg)
}
