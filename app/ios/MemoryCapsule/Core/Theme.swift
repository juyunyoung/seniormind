import SwiftUI

/// 색·크기. 와이어프레임(기억캡슐 UX 와이어프레임 사본, 11/6) 기준.
enum Theme {
    static let green = Color(hex: 0x1F5C4A)          // 주 버튼·강조
    static let text = Color(hex: 0x1E342B)
    static let background = Color(hex: 0xF8FAF7)     // 시니어 화면 바탕
    static let startBackground = Color(hex: 0xEEF2EC) // 시작 화면 바탕
    static let line = Color(hex: 0xDCE5DA)
    static let cardBorder = Color(hex: 0xD3DCD3)
    static let muted = Color(hex: 0x64776B)
    static let secondaryFill = Color(hex: 0xEEF1EC)
    static let secondaryBorder = Color(hex: 0xCFD8CF)
    static let selectedFill = Color(hex: 0xE5EEDF)
    static let selectedBorder = Color(hex: 0x6C8E60)
    static let focus = Color(hex: 0xB37A24)
    static let error = Color(hex: 0x93481F)
    static let caller = Color(hex: 0x56665C)
    static let bubble = Color(hex: 0xE3EEE6)
    static let callerBox = Color(hex: 0xEEF1EC)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// 주 버튼: 화면 폭 전체, 진한 초록.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Theme.green, in: RoundedRectangle(cornerRadius: 18))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
    }
}

/// 보조 버튼: 화면 폭 전체, 연한 회색 + 테두리.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(Theme.text.opacity(0.85))
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Theme.secondaryFill, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.secondaryBorder))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
    }
}
