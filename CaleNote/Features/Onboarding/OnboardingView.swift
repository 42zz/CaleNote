import SwiftUI

struct OnboardingView: View {
    private enum Step: Int, CaseIterable {
        case welcome
        case googleSignIn
        case initialSettings
        case tutorial

        var title: String {
            switch self {
            case .welcome:
                return L10n.tr("onboarding.step.welcome")
            case .googleSignIn:
                return L10n.tr("onboarding.step.google_sign_in")
            case .initialSettings:
                return L10n.tr("onboarding.step.initial_settings")
            case .tutorial:
                return L10n.tr("onboarding.step.tutorial")
            }
        }
    }

    @EnvironmentObject private var auth: GoogleAuthService
    @EnvironmentObject private var calendarListService: CalendarListService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("targetCalendarId") private var targetCalendarId: String = CalendarSettings.shared.targetCalendarId
    @AppStorage("syncWindowDaysPast") private var pastDays: Int = CalendarSettings.shared.syncWindowDaysPast
    @AppStorage("syncWindowDaysFuture") private var futureDays: Int = CalendarSettings.shared.syncWindowDaysFuture
    @AppStorage("displayWeekStartDay") private var weekStartDay: Int = DisplaySettings.defaultWeekStartDay

    @State private var step: Step = .welcome
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $step) {
                    welcomeStep
                        .tag(Step.welcome)

                    googleSignInStep
                        .tag(Step.googleSignIn)

                    initialSettingsStep
                        .tag(Step.initialSettings)

                    tutorialStep
                        .tag(Step.tutorial)
                }
                .tabViewStyle(.page)

                footer
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color.cnSurface)
            }
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.tr("common.skip")) {
                        completeOnboarding()
                    }
                    .accessibilityLabel(L10n.tr("onboarding.skip"))
                    .accessibilityHint(L10n.tr("onboarding.skip.hint"))
                    .accessibilityIdentifier("onboardingSkipButton")
                }
            }
        }
        .interactiveDismissDisabled(true)
        .task {
            if auth.isAuthenticated && calendarListService.calendars.isEmpty {
                await calendarListService.syncCalendarList()
            }
        }
        .onChange(of: targetCalendarId) { _, newValue in
            CalendarSettings.shared.targetCalendarId = newValue
        }
        .onChange(of: pastDays) { _, newValue in
            CalendarSettings.shared.syncWindowDaysPast = newValue
        }
        .onChange(of: futureDays) { _, newValue in
            CalendarSettings.shared.syncWindowDaysFuture = newValue
        }
    }

    private var footer: some View {
        HStack {
            Button(L10n.tr("common.back")) {
                moveStep(offset: -1)
            }
            .disabled(step == .welcome)
            .accessibilityIdentifier("onboardingBackButton")

            Spacer()

            Button(step == .tutorial ? L10n.tr("common.done") : L10n.tr("common.next")) {
                if step == .tutorial {
                    completeOnboarding()
                } else {
                    moveStep(offset: 1)
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("onboardingPrimaryButton")
        }
    }

    private var welcomeStep: some View {
        OnboardingStepContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.tr("onboarding.welcome.title"))
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(L10n.tr("onboarding.welcome.message"))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    Label(L10n.tr("onboarding.welcome.point.timeline"), systemImage: "calendar")
                    Label(L10n.tr("onboarding.welcome.point.sync"), systemImage: "arrow.triangle.2.circlepath")
                    Label(L10n.tr("onboarding.welcome.point.ui"), systemImage: "hand.tap")
                }
                .font(.subheadline)

                Button(L10n.tr("onboarding.step.skip")) {
                    moveStep(offset: 1)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .accessibilityIdentifier("onboardingStepSkipButton")
            }
        }
    }

    private var googleSignInStep: some View {
        OnboardingStepContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.tr("onboarding.google.message"))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("onboarding.google.permissions.title"))
                        .font(.headline)

                    Label(L10n.tr("onboarding.google.permissions.calendar"), systemImage: "checkmark.circle")
                    Label(L10n.tr("onboarding.google.permissions.access"), systemImage: "lock.shield")
                }
                .font(.subheadline)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("onboarding.google.privacy.title"))
                        .font(.headline)

                    Text(L10n.tr("onboarding.google.privacy.message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if auth.isAuthenticated {
                    Label(L10n.tr("onboarding.google.connected", auth.userEmail ?? L10n.tr("common.unknown")), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                        .accessibilityIdentifier("onboardingSignedInLabel")
                } else {
                    Button(L10n.tr("auth.google.sign_in")) {
                        Task {
                            do {
                                try await auth.signIn()
                                await calendarListService.syncCalendarList()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("onboardingGoogleSignInButton")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button(L10n.tr("onboarding.step.skip")) {
                    moveStep(offset: 1)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .accessibilityIdentifier("onboardingStepSkipButton")
            }
        }
    }

    private var initialSettingsStep: some View {
        OnboardingStepContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.tr("onboarding.settings.message"))
                    .foregroundStyle(.secondary)

                calendarSelectionSection

                Divider()

                syncWindowSection

                Divider()

                weekStartSection

                Button(L10n.tr("onboarding.step.skip")) {
                    moveStep(offset: 1)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .accessibilityIdentifier("onboardingStepSkipButton")
            }
        }
    }

    private var calendarSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("onboarding.settings.calendars.title"))
                .font(.headline)

            if !auth.isAuthenticated {
                Text(L10n.tr("onboarding.settings.calendars.sign_in_required"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if calendarListService.calendars.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(L10n.tr("onboarding.settings.calendars.loading"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button(L10n.tr("common.refresh")) {
                    Task {
                        await calendarListService.syncCalendarList()
                    }
                }
                .font(.footnote)
            } else {
                ForEach(calendarListService.calendars, id: \.calendarId) { calendar in
                    Toggle(isOn: Binding(
                        get: { calendar.isSyncEnabled },
                        set: { newValue in
                            if newValue != calendar.isSyncEnabled {
                                calendarListService.toggleCalendarSync(calendar.calendarId)
                            }
                        }
                    )) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(CalendarColor.color(from: calendar.backgroundColor, colorScheme: colorScheme))
                                .frame(width: 10, height: 10)
                            Text(calendar.summary)
                                .font(.subheadline)
                            if calendar.isPrimary {
                                Text(L10n.tr("calendar.primary"))
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor)
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .accessibilityIdentifier("onboardingCalendarToggle_\(calendar.calendarId)")
                }

                if let targetCalendar = writableCalendars.first(where: { $0.calendarId == targetCalendarId }) ?? writableCalendars.first {
                    Picker(L10n.tr("onboarding.settings.calendars.target"), selection: $targetCalendarId) {
                        ForEach(writableCalendars, id: \.calendarId) { calendar in
                            Text(calendar.summary)
                                .tag(calendar.calendarId)
                        }
                    }
                    .onAppear {
                        if targetCalendarId.isEmpty {
                            targetCalendarId = targetCalendar.calendarId
                        }
                    }
                    .accessibilityIdentifier("onboardingTargetCalendarPicker")
                } else {
                    Text(L10n.tr("onboarding.settings.calendars.no_writable"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var syncWindowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("onboarding.settings.sync_window"))
                .font(.headline)

            Stepper(L10n.tr("settings.sync_window.past", pastDays), value: $pastDays, in: 1...365)
            Stepper(L10n.tr("settings.sync_window.future", futureDays), value: $futureDays, in: 1...365)
        }
    }

    private var weekStartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("settings.display.week_start"))
                .font(.headline)

            Picker(L10n.tr("settings.display.week_start"), selection: $weekStartDay) {
                Text(L10n.tr("weekday.sunday")).tag(0)
                Text(L10n.tr("weekday.monday")).tag(1)
            }
            .pickerStyle(.segmented)
        }
    }

    private var tutorialStep: some View {
        OnboardingStepContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.tr("onboarding.tutorial.message"))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    Label(L10n.tr("onboarding.tutorial.point.add"), systemImage: "plus.circle.fill")
                    Label(L10n.tr("onboarding.tutorial.point.save"), systemImage: "square.and.pencil")
                    Label(L10n.tr("onboarding.tutorial.point.tags"), systemImage: "tag")
                    Label(L10n.tr("onboarding.tutorial.point.search"), systemImage: "magnifyingglass")
                }
                .font(.subheadline)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("onboarding.tutorial.example.title"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("onboarding.tutorial.example.entry_title"))
                            .font(.headline)
                        Text(L10n.tr("onboarding.tutorial.example.entry_detail"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cnSurfaceSecondary)
                    .cornerRadius(12)
                }

                Text(L10n.tr("onboarding.tutorial.footer"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var writableCalendars: [CalendarInfo] {
        calendarListService.calendars.filter { $0.isWritable }
    }

    private func moveStep(offset: Int) {
        guard let currentIndex = Step.allCases.firstIndex(of: step) else { return }
        let nextIndex = currentIndex + offset
        guard Step.allCases.indices.contains(nextIndex) else { return }
        step = Step.allCases[nextIndex]
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        dismiss()
    }
}

private struct OnboardingStepContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
