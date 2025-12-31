import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum CalendarColor {
    static func color(from hex: String?, colorScheme: ColorScheme) -> Color {
        guard let hex, let base = Color(hex: hex) else {
            return .accentColor
        }
        if colorScheme == .dark {
            return base.adjustedForDarkMode()
        }
        return base
    }
}

extension Color {
    func adjustedForDarkMode() -> Color {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        if uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            let tunedBrightness = min(0.92, max(0.35, brightness * 0.8 + 0.12))
            let tunedSaturation = min(1.0, max(0.25, saturation * 0.9))
            return Color(
                hue: Double(hue),
                saturation: Double(tunedSaturation),
                brightness: Double(tunedBrightness),
                opacity: Double(alpha)
            )
        }
        return Color(uiColor: uiColor.withAlphaComponent(0.95))
        #else
        return self
        #endif
    }
}
