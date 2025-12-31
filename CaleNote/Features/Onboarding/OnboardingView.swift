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
                return "CaleNoteへようこそ"
            case .googleSignIn:
                return "Googleアカウント連携"
            case .initialSettings:
                return "初期設定"
            case .tutorial:
                return "使い方のポイント"
            }
        }
    }

    @EnvironmentObject private var auth: GoogleAuthService
    @EnvironmentObject private var calendarListService: CalendarListService
    @Environment(\.dismiss) private var dismiss

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
                    .background(Color(uiColor: .systemBackground))
            }
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("スキップ") {
                        completeOnboarding()
                    }
                    .accessibilityLabel("オンボーディングをスキップ")
                    .accessibilityHint("後から設定画面で再表示できます")
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
            Button("戻る") {
                moveStep(offset: -1)
            }
            .disabled(step == .welcome)

            Spacer()

            Button(step == .tutorial ? "完了" : "次へ") {
                if step == .tutorial {
                    completeOnboarding()
                } else {
                    moveStep(offset: 1)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var welcomeStep: some View {
        OnboardingStepContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text("カレンダーに寄生する記録")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("CaleNoteは、カレンダーを見る流れを途切れさせずに記録できる体験を目指しています。")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    Label("予定と記録を同じタイムラインに表示", systemImage: "calendar")
                    Label("Googleカレンダーと双方向同期", systemImage: "arrow.triangle.2.circlepath")
                    Label("学習コストの低いUI", systemImage: "hand.tap")
                }
                .font(.subheadline)

                Button("このステップをスキップ") {
                    moveStep(offset: 1)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
        }
    }

    private var googleSignInStep: some View {
        OnboardingStepContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text("Googleカレンダーと同期するために、Googleアカウントの連携が必要です。")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("必要な権限")
                        .font(.headline)

                    Label("カレンダーの閲覧・作成・更新・削除", systemImage: "checkmark.circle")
                    Label("同期を維持するためのアクセス", systemImage: "lock.shield")
                }
                .font(.subheadline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("プライバシー")
                        .font(.headline)

                    Text("データはGoogleカレンダーを正として扱い、必要最小限のみローカルに保存します。いつでも設定からサインアウトできます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let user = auth.currentUser {
                    Label("連携済み: \(user.profile?.email ?? "Unknown")", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else {
                    Button("Googleでサインイン") {
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
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button("このステップをスキップ") {
                    moveStep(offset: 1)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
        }
    }

    private var initialSettingsStep: some View {
        OnboardingStepContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text("同期対象や表示設定を選んで、あなたのカレンダー体験に合わせます。")
                    .foregroundStyle(.secondary)

                calendarSelectionSection

                Divider()

                syncWindowSection

                Divider()

                weekStartSection

                Button("このステップをスキップ") {
                    moveStep(offset: 1)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
        }
    }

    private var calendarSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("同期対象カレンダー")
                .font(.headline)

            if !auth.isAuthenticated {
                Text("カレンダーを取得するにはGoogleサインインが必要です。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if calendarListService.calendars.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("カレンダーを取得しています…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button("再取得する") {
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
                                .fill(Color(hex: calendar.backgroundColor ?? "") ?? .accentColor)
                                .frame(width: 10, height: 10)
                            Text(calendar.summary)
                                .font(.subheadline)
                            if calendar.isPrimary {
                                Text("メイン")
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }

                if let targetCalendar = writableCalendars.first(where: { $0.calendarId == targetCalendarId }) ?? writableCalendars.first {
                    Picker("書き込み先", selection: $targetCalendarId) {
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
                } else {
                    Text("書き込み可能なカレンダーが見つかりません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var syncWindowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("同期範囲")
                .font(.headline)

            Stepper("過去: \(pastDays)日", value: $pastDays, in: 1...365)
            Stepper("未来: \(futureDays)日", value: $futureDays, in: 1...365)
        }
    }

    private var weekStartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("週の開始曜日")
                .font(.headline)

            Picker("開始曜日", selection: $weekStartDay) {
                Text("日曜日").tag(0)
                Text("月曜日").tag(1)
            }
            .pickerStyle(.segmented)
        }
    }

    private var tutorialStep: some View {
        OnboardingStepContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text("日々の記録は、カレンダーを見る延長で完結します。")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    Label("右下の＋から記録を追加", systemImage: "plus.circle.fill")
                    Label("タイトルと本文を入力して保存", systemImage: "square.and.pencil")
                    Label("#タグで整理", systemImage: "tag")
                    Label("検索から過去の記録を探す", systemImage: "magnifyingglass")
                }
                .font(.subheadline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("エントリー例")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("朝の振り返り")
                            .font(.headline)
                        Text("7:30 / #習慣 #メモ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)
                }

                Text("いつでも設定画面からオンボーディングを見直せます。")
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
