import SwiftUI

/// R3 안전 화면(시니어). 문구·번호는 항상 설정 파일 값(앱 계획서 1.6). 앱이 자동 신고하지 않는다.
/// 대화(세션)는 끊지 않는다. 기억이는 같은 문구를 소리로 읽는다(데이터 채널로 전달).
struct SafetyView: View {
    let phrase: SafetyPhrase
    let guardianNotified: Bool
    let close: () -> Void

    var body: some View {
        let safety = ConfigStore.shared.current.safety
        let numbers = (phrase.numbers?.isEmpty == false) ? phrase.numbers! : ["119"]
        VStack(spacing: 22) {
            Spacer(minLength: 8)
            Image(systemName: "heart.text.square.fill").font(.system(size: 52)).foregroundStyle(Theme.error)
            Text(phrase.text).font(.system(size: 26, weight: .bold)).multilineTextAlignment(.center).lineSpacing(6)
            VStack(spacing: 12) {
                ForEach(numbers, id: \.self) { number in
                    let name = safety.contacts?.first { $0.number == number }?.name ?? number
                    Link(destination: URL(string: "tel://\(number.replacingOccurrences(of: "-", with: ""))")!) {
                        Label("\(name) \(number)", systemImage: "phone.fill")
                            .font(.title2.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .foregroundStyle(.white)
                            .background(Theme.error, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            if guardianNotified {
                Label("보호자에게 알렸어요", systemImage: "person.2.fill")
                    .font(.title3.weight(.semibold)).foregroundStyle(Theme.green)
            }
            Spacer()
            Button("기억이와 이야기 계속하기", action: close)
                .buttonStyle(SecondaryButtonStyle()).frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }
}
