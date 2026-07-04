import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// 디자인 번들의 다크/골드 팔레트
enum Theme {
    static let bgTop = Color(hex: 0x0A0A0C)
    static let bgBottom = Color(hex: 0x101014)
    static let card = Color(hex: 0x141419)
    static let cardAlt = Color(hex: 0x16161B)
    static let heroTop = Color(hex: 0x17171D)
    static let heroBottom = Color(hex: 0x101013)
    static let gold = Color(hex: 0xD4B36A)
    static let goldLight = Color(hex: 0xE9CD8D)
    static let goldDark = Color(hex: 0xB78F3E)
    static let text = Color(hex: 0xF2F2F4)
    static let textStrong = Color(hex: 0xE8E8EA)
    static let muted = Color(hex: 0x8A8B93)
    static let muted2 = Color(hex: 0x9A9BA3)
    static let silver = Color(hex: 0xC9CDD4)
    static let green = Color(hex: 0x6FBF8A)
    static let orange = Color(hex: 0xFF7A2F)
    static let ink = Color(hex: 0x141414)

    static let goldGradient = LinearGradient(
        colors: [goldLight, goldDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let leaseGradient = LinearGradient(
        colors: [gold, orange],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let cardBorder = Color.white.opacity(0.06)
}
