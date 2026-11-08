import SwiftUI

/// 보호자 화면 공통 틀: 내비게이션 제목 + 스크롤 본문 + 아래 버튼.
struct GuardianScaffold<Content: View, Bottom: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var bottom: () -> Bottom

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content() }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            if Bottom.self != EmptyView.self {
                VStack(spacing: 10) { bottom() }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
                    .background(Theme.background)
            }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension GuardianScaffold where Bottom == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, content: content, bottom: { EmptyView() })
    }
}

/// 흰 카드(제목 + 오른쪽 "자세히" 등)
struct GuardianCard<Content: View>: View {
    var title: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || trailing != nil {
                HStack {
                    if let title { Text(title).font(.system(size: 19, weight: .bold)) }
                    Spacer()
                    if let trailing { trailing }
                }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.cardBorder))
    }
}

/// 목록 한 줄(설정·연결 메뉴). NavigationLink나 Button의 label로 쓴다.
struct GuardianRowLabel: View {
    let title: String
    var detail: String? = nil
    var tint: Color = Theme.text

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 19, weight: .bold)).foregroundStyle(tint)
                if let detail { Text(detail).font(.system(size: 16)).foregroundStyle(Theme.muted) }
            }
            Spacer(minLength: 8)
            Text("›").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.cardBorder))
        .contentShape(Rectangle())
    }
}

/// 하나만 고르는 선택지(G18 등급, G27 반복 주기)
struct GuardianOptionRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 19, weight: .semibold)).foregroundStyle(selected ? Theme.green : Theme.text)
                Spacer()
                if selected { Image(systemName: "checkmark").font(.headline).foregroundStyle(Theme.green) }
            }
            .padding(.horizontal, 18).frame(maxWidth: .infinity, minHeight: 58)
            .background(selected ? Theme.bubble : .white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Theme.selectedBorder : Theme.cardBorder, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 입력 칸(이메일·비밀번호·이름·번호)
struct GuardianField: View {
    enum Kind { case text, email, password, code }
    let label: String
    @Binding var text: String
    var kind: Kind = .text
    var placeholder: String = ""

    init(_ label: String, text: Binding<String>, kind: Kind = .text, placeholder: String = "") {
        self.label = label; self._text = text; self.kind = kind; self.placeholder = placeholder
    }

    private var contentType: UITextContentType {
        switch kind { case .email: .emailAddress; case .password: .password; case .code: .oneTimeCode; case .text: .name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 17, weight: .bold))
            Group {
                if kind == .password { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
            }
            .font(kind == .code ? Font.system(size: 30, weight: .bold).monospacedDigit() : Font.system(size: 19))
            .keyboardType(kind == .email ? UIKeyboardType.emailAddress : kind == .code ? UIKeyboardType.numberPad : UIKeyboardType.default)
            .textContentType(contentType)
            .textInputAutocapitalization(kind == .text ? TextInputAutocapitalization.words : TextInputAutocapitalization.never)
            .autocorrectionDisabled(kind != .text)
            .padding(.horizontal, 16).frame(minHeight: 56)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder, lineWidth: 1.2))
            .accessibilityLabel(label)
        }
    }
}

struct GuardianErrorText: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.error)
            .accessibilityElement(children: .combine)
    }
}

/// 작은 태그(요약 카드)
struct GuardianTag: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.green)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.selectedFill, in: Capsule())
    }
}

/// G11 · 연결을 확인해 주세요
struct GuardianErrorView: View {
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 40)).foregroundStyle(Theme.muted)
            Text("연결을 확인해 주세요").font(.system(size: 22, weight: .bold))
            Text("인터넷 연결을 확인하고 다시 불러와 주세요.").font(.system(size: 17)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button("다시 불러오기", action: retry).buttonStyle(SecondaryButtonStyle()).padding(.top, 8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

/// G10 · 아직 대화 기록이 없어요
struct GuardianEmptyView: View {
    var body: some View {
        VStack(spacing: 14) {
            SmallBird(size: 120)
            Text("아직 대화 기록이 없어요.").font(.system(size: 22, weight: .bold))
            Text("부모님이 기억이와 대화하면\n이곳에서 기록을 볼 수 있어요.").font(.system(size: 17)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}
