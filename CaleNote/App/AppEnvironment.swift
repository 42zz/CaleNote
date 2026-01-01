import Foundation
import UIKit

enum AppEnvironment {
    static let arguments = ProcessInfo.processInfo.arguments

    static let isUITesting = arguments.contains("UI_TESTING")
    static let shouldResetUserDefaults = arguments.contains("UI_TESTING_RESET")
    static let shouldSeedData = arguments.contains("UI_TESTING_SEED")
    static let shouldCompleteOnboarding = arguments.contains("UI_TESTING_COMPLETE_ONBOARDING")
    static let shouldSkipSync = arguments.contains("UI_TESTING_SKIP_SYNC") || isUITesting
    static let useMockAuth = arguments.contains("UI_TESTING_MOCK_AUTH") || isUITesting

    static var interfaceStyle: UIUserInterfaceStyle? {
        if arguments.contains("UI_TESTING_DARK_MODE") { return .dark }
        if arguments.contains("UI_TESTING_LIGHT_MODE") { return .light }
        return nil
    }

    static func applyOverrides() {
        if shouldResetUserDefaults, let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
        }

        if shouldCompleteOnboarding {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }

        if let style = interfaceStyle {
            UIView.appearance().overrideUserInterfaceStyle = style
        }
    }
}
