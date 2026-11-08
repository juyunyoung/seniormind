import SwiftUI

/// G01 로그인(G02 오류 포함) → G29 회원가입 / G30 비밀번호 찾기(G31 결과)
struct GuardianLoginView: View {
    @Environment(AppState.self) private var app
    @Environment(GuardianStore.self) private var store
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @State private var route: Route?
    enum Route: Hashable { case signUp, reset }

    var body: some View {
        NavigationStack {
            GuardianScaffold(title: "") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("가족의 안부를 살펴봐요").font(.system(size: 28, weight: .bold))
                    Text("마음 상태·대화량·감정 변화와\n확인이 필요한 신호를 봐요.").font(.system(size: 17)).foregroundStyle(Theme.muted)
                }
                .padding(.bottom, 8)
                GuardianField("이메일", text: $email, kind: .email, placeholder: "name@example.com")
                GuardianField("비밀번호", text: $password, kind: .password)
                if let error { GuardianErrorText(text: error) }   // G02
            } bottom: {
                Button(busy ? "로그인 중…" : "로그인") { Task { await login() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(email.isEmpty || password.isEmpty || busy)
                HStack(spacing: 18) {
                    Button("회원가입") { route = .signUp }
                    Text("|").foregroundStyle(Theme.line)
                    Button("비밀번호 찾기") { route = .reset }
                }
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.green)
                .frame(minHeight: 44)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("‹ 이전") { app.backToRoleSelect() }.accessibilityLabel("역할 다시 고르기") }
            }
            .navigationDestination(item: $route) { r in
                switch r {
                case .signUp: GuardianSignUpView()
                case .reset: GuardianResetView(email: email)
                }
            }
        }
        .tint(Theme.green)
    }

    private func login() async {
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await app.auth.signInGuardian(email: email.trimmingCharacters(in: .whitespaces), password: password)
            store.signedIn = true
            await app.bootstrap()
        } catch let e as AuthError {
            error = e.errorDescription
        } catch {
            self.error = AuthError.invalidCredentials.errorDescription
        }
    }
}

/// G29 회원가입
struct GuardianSignUpView: View {
    @Environment(AppState.self) private var app
    @Environment(GuardianStore.self) private var store
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        GuardianScaffold(title: "회원가입") {
            GuardianField("이메일", text: $email, kind: .email, placeholder: "name@example.com")
            GuardianField("비밀번호", text: $password, kind: .password, placeholder: "6자 이상")
            GuardianField("비밀번호 확인", text: $confirm, kind: .password)
            if !confirm.isEmpty, confirm != password { GuardianErrorText(text: "비밀번호가 서로 달라요.") }
            if let error { GuardianErrorText(text: error) }
        } bottom: {
            Button(busy ? "가입 중…" : "다음") { Task { await signUp() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!email.contains("@") || password.count < 6 || password != confirm || busy)
        }
    }

    private func signUp() async {
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await app.auth.signUpGuardian(email: email.trimmingCharacters(in: .whitespaces), password: password)
            store.signedIn = true          // → G28 보호자 정보 확인
            await app.bootstrap()
        } catch let e as AuthError { error = e.errorDescription }
        catch { self.error = AuthError.network.errorDescription }
    }
}

/// G30 비밀번호 찾기 → G31 안내
struct GuardianResetView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var email: String
    @State private var sent = false
    @State private var busy = false

    var body: some View {
        GuardianScaffold(title: "비밀번호 찾기") {
            if sent {
                Image(systemName: "envelope.badge").font(.system(size: 40)).foregroundStyle(Theme.green)
                Text("가입된 이메일이라면 재설정 안내를 보내드려요.\n받은 편지함을 확인해 주세요.")
                    .font(.system(size: 20, weight: .semibold)).lineSpacing(4)
            } else {
                Text("비밀번호 변경 안내를 이 이메일로 받아요.").font(.system(size: 20, weight: .semibold))
                GuardianField("이메일", text: $email, kind: .email, placeholder: "name@example.com")
            }
        } bottom: {
            if sent {
                Button("로그인으로 돌아가기") { dismiss() }.buttonStyle(PrimaryButtonStyle())
            } else {
                Button(busy ? "보내는 중…" : "재설정 안내 받기") { Task { await send() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!email.contains("@") || busy)
            }
        }
    }

    private func send() async {
        busy = true; defer { busy = false }
        try? await app.auth.sendPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
        sent = true
    }
}

/// G28 보호자 정보 확인(이름)
struct GuardianProfileView: View {
    @Environment(AppState.self) private var app
    @Environment(GuardianStore.self) private var store
    @State private var name = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            GuardianScaffold(title: "보호자 정보 확인") {
                Text("부모님 앱과 알림에 보일 이름이에요.").font(.system(size: 18)).foregroundStyle(Theme.muted)
                GuardianField("이름", text: $name, placeholder: "예: 김민수")
            } bottom: {
                Button("저장하고 부모님 연결") { Task { await save() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("로그아웃") { try? app.auth.signOut(); store.signedOut() }
                }
            }
        }
        .tint(Theme.green)
    }

    private func save() async {
        busy = true; defer { busy = false }
        await store.saveProfile(name: name.trimmingCharacters(in: .whitespaces), api: app.api)
        await app.bootstrap()
    }
}
