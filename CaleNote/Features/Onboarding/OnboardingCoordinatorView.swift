import SwiftUI

struct OnboardingCoordinatorView: View {
    @EnvironmentObject private var auth: GoogleAuthService

    @State private var currentStep: OnboardingStep = .signIn

    let onComplete: () -> Void

    enum OnboardingStep {
        case signIn
        case selectCalendars
    }

    var body: some View {
        Group {
            switch currentStep {
            case .signIn:
                GoogleSignInOnboardingView {
                    // ステップ1完了 → ステップ2へ
                    currentStep = .selectCalendars
                }
                .environmentObject(auth)

            case .selectCalendars:
                CalendarSelectionOnboardingView {
                    // ステップ2完了 → オンボーディング終了
                    onComplete()
                }
            }
        }
    }
}
