import SwiftUI
import UIKit

extension Color {
    init(light: UInt32, dark: UInt32) {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}

enum Theme {
    static let accent = Color(light: 0x1C7A3C, dark: 0x4CC474)
    /// Text on top of the accent color (dark text on the brighter dark-mode green).
    static let accentText = Color(light: 0xFFFFFF, dark: 0x06220F)
    static let warn = Color(light: 0xB3261E, dark: 0xFF8A7D)
    static let benchBG = Color(light: 0xEEF1ED, dark: 0x202A23)
    static let benchFG = Color(light: 0x6B776E, dark: 0x8D9A91)

    private static let groupBG = [
        Color(light: 0xFDE8B3, dark: 0x4A3A0C),
        Color(light: 0xD7E6FB, dark: 0x16324F),
        Color(light: 0xD2EFD8, dark: 0x163D22),
        Color(light: 0xFBDBD5, dark: 0x4D1D15),
    ]
    private static let groupFG = [
        Color(light: 0x6A4800, dark: 0xFFDF8A),
        Color(light: 0x12407A, dark: 0xB5D5FB),
        Color(light: 0x135428, dark: 0xAEE5BB),
        Color(light: 0x8A2415, dark: 0xFFC0B3),
    ]

    /// Colors by line: 0 keeper, 1 defense, 2 midfield, 3 forward; nil = bench.
    static func background(group: Int?) -> Color { group.map { groupBG[$0] } ?? benchBG }
    static func foreground(group: Int?) -> Color { group.map { groupFG[$0] } ?? benchFG }
}
