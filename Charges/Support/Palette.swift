import SwiftUI
import UIKit

/// Validated categorical palette (fixed slot order, separate light/dark steps).
/// Categories own a slot permanently, so a filter never repaints survivors.
enum Palette {
    static let blue = Color(light: 0x2A78D6, dark: 0x3987E5)
    static let orange = Color(light: 0xEB6834, dark: 0xD95926)
    static let aqua = Color(light: 0x1BAF7A, dark: 0x199E70)
    static let yellow = Color(light: 0xEDA100, dark: 0xC98500)
    static let magenta = Color(light: 0xE87BA4, dark: 0xD55181)
    static let green = Color(light: 0x008300, dark: 0x008300)
    static let violet = Color(light: 0x4A3AA7, dark: 0x9085E9)
    static let red = Color(light: 0xE34948, dark: 0xE66767)
    static let gray = Color(light: 0x898781, dark: 0x898781)
    static let quiet = Color(light: 0xC3C2B7, dark: 0x383835)

    /// Single-series marks (daily bars).
    static let series = blue
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
