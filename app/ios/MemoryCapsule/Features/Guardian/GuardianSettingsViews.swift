import SwiftUI
import UserNotifications

/// G16 · 보호자 설정 (G20 연결 해제 확인)
struct GuardianSettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(GuardianStore.self) private var store
    @State private var confirmUnlink = false
    @State private var error: String?

    var body: some View {
        GuardianScaffold(title: "보호자 설정") {
            GuardianCard(title: "연결된 부모님") {
                Text("\(store.seniorName)님").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.green)
                if let l = store.current {
                    Text("\(l.linkedAt.formatted(date: .long, time: .omitted))에 연결했어요").font(.system(size: 15)).foregroundStyle(Theme.muted)
                }
            }
            NavigationLink { GuardianAlertPrefsView() } label: { GuardianRowLabel(title: "신호 알림 수신 방법과 설정") }
                .buttonStyle(.plain)
            NavigationLink { GuardianPrivacyInfoView() } label: { GuardianRowLabel(title: "정보 보관·공유 안내") }
                .buttonStyle(.plain)
            Button { confirmUnlink = true } label: {
                GuardianRowLabel(title: "보호자 연결 해제", detail: "먼저 한 번 더 확인해요", tint: Theme.error)
            }
            .buttonStyle(.plain)
            if let error { GuardianErrorText(text: error) }
            if let name = store.guardianName {
                Text("보호자: \(name)").font(.system(size: 15)).foregroundStyle(Theme.muted).padding(.top, 8)
            }
        } bottom: {
            Button("로그아웃") { try? app.auth.signOut(); store.signedOut() }.buttonStyle(SecondaryButtonStyle())
        }
        .alert("연결을 해제할까요?", isPresented: $confirmUnlink) {   // G20
            Button("취소", role: .cancel) {}
            Button("연결 해제", role: .destructive) { Task { await unlink() } }
        } message: {
            Text("해제하면 부모님의 상태와 새 신호를 확인할 수 없어요.")
        }
    }

    private func unlink() async {
        do { try await store.unlink(app.api) } catch { self.error = "해제하지 못했어요. 잠시 후 다시 해 주세요." }
    }
}

/// G18 · 신호 알림 수신 방법과 설정
struct GuardianAlertPrefsView: View {
    @Environment(AppState.self) private var app
    @Environment(GuardianStore.self) private var store
    @State private var permission: UNAuthorizationStatus = .notDetermined

    var body: some View {
        GuardianScaffold(title: "신호 알림 설정") {
            GuardianCard(title: "알림 받는 방법") {
                Text(permissionText).font(.system(size: 17))
                if permission != .authorized && permission != .provisional {
                    Button("알림 허용하기") { Task { await requestPermission() } }.buttonStyle(SecondaryButtonStyle())
                }
            }
            Text("받을 알림 등급").font(.system(size: 17, weight: .bold)).padding(.top, 4)
            GuardianOptionRow(title: "확인이 필요한 신호부터", selected: store.prefs.riskMinLevel != "R3") { store.prefs.riskMinLevel = "R2" }
            GuardianOptionRow(title: "긴급한 신호만", selected: store.prefs.riskMinLevel == "R3") { store.prefs.riskMinLevel = "R3" }
            Text("긴급한 신호는 등급과 관계없이 항상 알려 드려요.").font(.system(size: 15)).foregroundStyle(Theme.muted)
            GuardianCard {
                Toggle("일정 미확인 알림", isOn: Binding(get: { store.prefs.scheduleMissed ?? true }, set: { store.prefs.scheduleMissed = $0 }))
                Divider()
                Toggle("주간 리포트", isOn: Binding(get: { store.prefs.weeklyReport ?? true }, set: { store.prefs.weeklyReport = $0 }))
            }
            .font(.system(size: 18, weight: .semibold))
            .tint(Theme.green)
        }
        .task { permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        .onChange(of: store.prefs) { _, _ in Task { await store.savePrefs(app.api) } }
    }

    private var permissionText: String {
        switch permission {
        case .authorized, .provisional, .ephemeral: "이 휴대폰으로 푸시 알림을 받아요."
        case .denied: "휴대폰 설정에서 알림이 꺼져 있어요. 설정 앱에서 켜 주세요."
        default: "알림을 허용하면 확인이 필요한 신호를 바로 알려 드려요."
        }
    }

    private func requestPermission() async {
        if permission == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
            _ = await UIApplication.shared.open(url); return
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        await app.registerDevice(fcmToken: PushTokenStore.token)
    }
}

/// G19 · 정보 보관·공유 안내. 문구는 L13 확정본으로 바꾼다.
struct GuardianPrivacyInfoView: View {
    @State private var showPolicy = false

    var body: some View {
        GuardianScaffold(title: "정보 보관·공유 안내") {
            GuardianCard(title: "보호자와 공유하는 정보") {
                bullet("마음 상태 요약과 감정 변화")
                bullet("대화량(대화한 횟수)")
                bullet("확인이 필요한 신호 알림")
                bullet("약·일정 알림을 확인했는지")
            }
            GuardianCard(title: "보호자에게 보이지 않는 정보") {
                bullet("대화 원문과 음성")
                bullet("기억 카드에 남긴 이야기 내용")
            }
            Text("부모님이 동의를 거두거나 연결을 해제하면 새 정보는 더 이상 공유되지 않아요.")
                .font(.system(size: 15)).foregroundStyle(Theme.muted)
        } bottom: {
            Button("개인정보 처리 안내 보기") { showPolicy = true }.buttonStyle(SecondaryButtonStyle())
        }
        .sheet(isPresented: $showPolicy) {
            NavigationStack {
                GuardianScaffold(title: "개인정보 처리 안내") {
                    Text("개인정보 처리 안내 문구를 준비하고 있어요.").font(.system(size: 18))
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { showPolicy = false } } }
            }
            .tint(Theme.green)
        }
    }

    private func bullet(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) { Text("·").bold(); Text(t) }.font(.system(size: 17))
    }
}
