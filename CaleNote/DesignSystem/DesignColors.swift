import SwiftUI

enum DesignColors {
    static let background = Color("CNBackground")
    static let surface = Color("CNSurface")
    static let surfaceSecondary = Color("CNSurfaceSecondary")
    static let textPrimary = Color("CNTextPrimary")
    static let textSecondary = Color("CNTextSecondary")
    static let border = Color("CNBorder")
    static let divider = Color("CNDivider")
    static let overlay = Color("CNOverlay")
}

extension Color {
    static var cnBackground: Color { DesignColors.background }
    static var cnSurface: Color { DesignColors.surface }
    static var cnSurfaceSecondary: Color { DesignColors.surfaceSecondary }
    static var cnTextPrimary: Color { DesignColors.textPrimary }
    static var cnTextSecondary: Color { DesignColors.textSecondary }
    static var cnBorder: Color { DesignColors.border }
    static var cnDivider: Color { DesignColors.divider }
    static var cnOverlay: Color { DesignColors.overlay }
}
