import SwiftUI

/// 시니어 화면 공통 틀: 위쪽 막대("‹ 이전" / "설정·도움") + 구분선 + 본문 + 아래 버튼.
struct SeniorScaffold<Content: View, Bottom: View>: View {
    var onBack: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    var settingsDisabled = false
    @ViewBuilder var content: () -> Content
    @ViewBuilder var bottom: () -> Bottom

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let onBack {
                    Button(action: onBack) {
                        Text("‹ 이전").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.green)
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityLabel("이전 화면")
                }
                Spacer()
                if let onSettings {
                    Button(action: onSettings) {
                        Text("설정·도움").font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.green)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Theme.bubble, in: Capsule())
                            .overlay(Capsule().stroke(Theme.cardBorder))
                    }
                    .disabled(settingsDisabled)
                }
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 20)
            Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 0) { content() }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 12) { bottom() }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
    }
}

extension SeniorScaffold where Bottom == EmptyView {
    init(onBack: (() -> Void)? = nil, onSettings: (() -> Void)? = nil, settingsDisabled: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(onBack: onBack, onSettings: onSettings, settingsDisabled: settingsDisabled, content: content, bottom: { EmptyView() })
    }
}

/// 기억이 말풍선(아래 꼬리). 와이어프레임의 연초록 말풍선.
struct SpeechBubble: View {
    let text: String
    var size: CGFloat = 28

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .lineSpacing(6)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 26).padding(.vertical, 20)
            .frame(maxWidth: 520)
            .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 28))
            .overlay(alignment: .bottom) {
                BubbleTail().fill(Theme.bubble).frame(width: 24, height: 13).offset(y: 12)
            }
            .accessibilityLabel("기억이: \(text)")
    }
}

private struct BubbleTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath(); return p
    }
}

/// 흰 카드형 선택 줄(P01 "QR코드 보여주기 ›", S08 "말하는 속도 · 보통" 등).
struct SeniorMenuRow: View {
    let title: String
    var detail: String? = nil
    var trailing: String? = "›"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 23, weight: .bold)).foregroundStyle(Theme.text)
                    if let detail { Text(detail).font(.system(size: 18)).foregroundStyle(Theme.muted) }
                }
                Spacer(minLength: 8)
                if let trailing { Text(trailing).font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.text) }
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 20).padding(.vertical, 20)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.cardBorder))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// 흰 정보 카드(P03 인증번호 등).
struct SeniorCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.cardBorder))
    }
}

/// 작은 기억이(설정·연결 화면 말풍선 아래). 표정은 기본.
struct SmallBird: View {
    @State private var bird = BirdModel()
    var size: CGFloat = 150
    var body: some View { BirdView(model: bird).frame(width: size, height: size).accessibilityHidden(true) }
}
