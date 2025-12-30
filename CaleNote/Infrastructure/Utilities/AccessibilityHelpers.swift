import SwiftUI

enum AccessibilityAnimation {
    static func perform(_ animation: Animation? = .default, reduceMotion: Bool, _ action: () -> Void) {
        if reduceMotion {
            action()
        } else {
            withAnimation(animation) {
                action()
            }
        }
    }
}

extension View {
    @ViewBuilder
    func accessibilityValueText(_ value: String?) -> some View {
        if let value, !value.isEmpty {
            self.accessibilityValue(value)
        } else {
            self
        }
    }
}
