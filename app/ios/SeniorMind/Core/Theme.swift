import SwiftUI

/// PoC style.css의 색과 크기를 그대로 옮긴 값.
enum Theme {
    static let green = Color(hex: 0x255C45)
    static let text = Color(hex: 0x26372D)
    static let background = Color(hex: 0xF8FAF7)
    static let line = Color(hex: 0xDCE5DA)
    static let muted = Color(hex: 0x59685E)
    static let secondaryFill = Color(hex: 0xE7EEE4)
    static let selectedFill = Color(hex: 0xE5EEDF)
    static let selectedBorder = Color(hex: 0x6C8E60)
    static let focus = Color(hex: 0xB37A24)
    static let error = Color(hex: 0x93481F)
    static let caller = Color(hex: 0x56665C)
    static let bubble = Color(hex: 0xE4EFE6)
    static let callerBox = Color(hex: 0xFFFFFF)
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

/// PoC `.primary` 버튼.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .frame(minWidth: 230, minHeight: 56)
            .padding(.horizontal, 24)
            .background(Theme.green, in: RoundedRectangle(cornerRadius: 14))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.55)
    }
}

/// PoC `.secondary` 버튼.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.green)
            .frame(minHeight: 56)
            .padding(.horizontal, 24)
            .background(Theme.secondaryFill, in: RoundedRectangle(cornerRadius: 14))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.55)
    }
}
