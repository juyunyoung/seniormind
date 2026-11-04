import SwiftUI
import CoreImage.CIFilterBuiltins

/// S08 설정·도움(시니어): 보호자 등록(QR), 연결된 보호자·연결 끊기, 동의 확인·철회, 알람 권한. 앱 계획서 1.1·2.1.
struct SeniorSettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var links: [GuardianLink] = []
    @State private var showPairing = false
    @State private var needsConsent = false
    @State private var unlinkTarget: GuardianLink?
    @State private var consents: [ConsentType: Bool] = [:]

    private struct ConsentRow: Identifiable { let type: ConsentType; let title: String; var id: String { type.rawValue } }
    private let seniorTypes: [ConsentRow] = [
        .init(type: .voiceTransfer, title: "목소리 전송"), .init(type: .transcriptStore, title: "대화 내용 보관"),
        .init(type: .memoryCard, title: "기억 카드"), .init(type: .sensitive, title: "힘든 신호 알림"),
        .init(type: .guardianShare, title: "보호자에게 요약 보이기"), .init(type: .scheduleShare, title: "약·일정 함께 챙기기"),
        .init(type: .guardianTopicShare, title: "이야기 나눈 주제 보이기"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { startPairing() } label: {
                        Label("보호자 등록", systemImage: "qrcode").font(.title3.weight(.semibold))
                    }
                    .frame(minHeight: 56)
                }
                Section("연결된 보호자") {
                    if links.isEmpty { Text("아직 연결된 보호자가 없어요.").foregroundStyle(Theme.muted) }
                    ForEach(links) { link in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(link.displayName ?? link.relation ?? "보호자").font(.headline)
                                Text(link.linkedAt.formatted(date: .abbreviated, time: .omitted)).font(.footnote).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Button("연결 끊기", role: .destructive) { unlinkTarget = link }.buttonStyle(.bordered)
                        }
                        .frame(minHeight: 56)
                    }
                }
                Section {
                    ForEach(seniorTypes) { row in
                        Toggle(row.title, isOn: Binding(get: { consents[row.type] ?? false }, set: { set(row.type, $0) }))
                            .font(.title3).frame(minHeight: 48)
                    }
                } header: { Text("동의 확인·철회") } footer: {
                    Text("목소리 전송과 대화 내용 보관을 끄면 기억이와 대화할 수 없어요.")
                }
                Section("알람") {
                    Button("알람 권한 확인") { Task { _ = await AlarmScheduler.shared.requestPermission() } }
                }
            }
            .navigationTitle("설정·도움")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
            .task { loadConsents(); await reload() }
            .sheet(isPresented: $needsConsent) {
                // 보호자 연결 전 4~7단계 동의(앱 계획서 1.1, 2.1)
                ConsentFlowView(role: .senior, steps: ConsentStep.seniorGuardian) {
                    UserDefaults.standard.set(true, forKey: "mc.consent.guardianShare")
                    loadConsents()
                    needsConsent = false
                    showPairing = true
                }
            }
            .fullScreenCover(isPresented: $showPairing) {
                PairingQRView { Task { await reload() } }
            }
            .confirmationDialog("보호자 연결을 끊을까요?", isPresented: Binding(get: { unlinkTarget != nil }, set: { if !$0 { unlinkTarget = nil } }),
                                titleVisibility: .visible) {
                Button("연결 끊기", role: .destructive) {
                    if let target = unlinkTarget { Task { try? await app.api.unlink(linkId: target.linkId); await reload() } }
                }
            }
        }
    }

    private func startPairing() {
        let ok = (consents[.guardianShare] ?? false) && (consents[.scheduleShare] ?? false)
        if ok { showPairing = true } else { needsConsent = true }
    }

    private func reload() async {
        links = (try? await app.api.links()) ?? []
        app.hasGuardian = !links.isEmpty
    }

    private func loadConsents() {
        var map: [ConsentType: Bool] = [:]
        for row in seniorTypes { map[row.type] = UserDefaults.standard.bool(forKey: "mc.consent.\(row.type.rawValue)") }
        consents = map
    }

    private func set(_ type: ConsentType, _ granted: Bool) {
        consents[type] = granted
        UserDefaults.standard.set(granted, forKey: "mc.consent.\(type.rawValue)")
        Task { try? await app.api.postConsent(.init(type: type, version: ConsentStep.version, granted: granted,
                                                    method: "screen_tap", linkedSeniorId: nil)) }
    }
}

/// QR 표시 화면. 서버가 준 qr_payload를 그대로 그린다(두 OS가 같은 내용).
struct PairingQRView: View {
    var onLinked: () -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var pairing: PairingCode?
    @State private var remaining = 300
    @State private var linked = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            if linked {
                Spacer()
                Image(systemName: "checkmark.circle.fill").font(.system(size: 80)).foregroundStyle(Theme.green)
                Text("연결됐어요").font(.system(size: 32, weight: .bold))
                Spacer()
                Button("확인") { onLinked(); dismiss() }.buttonStyle(PrimaryButtonStyle())
            } else {
                Text("자녀분께 이 화면을 보여 주세요").font(.system(size: 28, weight: .bold)).multilineTextAlignment(.center)
                if let pairing, let image = qrImage(pairing.qrPayload) {
                    Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                        .frame(maxWidth: 300).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityLabel("보호자 등록 QR 코드")
                    // 카메라가 어려우면 숫자로 입력(두 OS 공통)
                    Text(pairing.code.map { String($0) }.joined(separator: " "))
                        .font(.system(size: 34, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.green)
                        .accessibilityLabel("연결 번호 \(pairing.code.map { String($0) }.joined(separator: " "))")
                    Text("\(remaining / 60)분 \(remaining % 60)초 남았어요").foregroundStyle(Theme.muted)
                } else if let error {
                    Text(error).foregroundStyle(Theme.error)
                } else { ProgressView() }
                Spacer()
                if remaining == 0 { Button("다시 만들기") { Task { await load() } }.buttonStyle(PrimaryButtonStyle()) }
                Button("닫기") { dismiss() }.buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .task { await load() }
        .task {
            // 연결 완료 감지: 푸시(pairing_done) 또는 10초 폴링(app_spec 2.1)
            let before = (try? await app.api.links().count) ?? 0
            while !Task.isCancelled && !linked {
                try? await Task.sleep(for: .seconds(10))
                if let now = try? await app.api.links().count, now > before { linked = true }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if let p = pairing { remaining = max(0, Int(p.expiresAt.timeIntervalSinceNow)) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pairingDone)) { _ in linked = true }
    }

    private func load() async {
        do { pairing = try await app.api.pairingCode(); error = nil }
        catch let e as APIError where e.code == "consent_required" { error = "먼저 보호자 공유 동의가 필요해요." }
        catch { self.error = "지금은 연결이 어려워요. 잠시 후 다시 해 주세요." }
    }

    private func qrImage(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage?.transformed(by: .init(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
