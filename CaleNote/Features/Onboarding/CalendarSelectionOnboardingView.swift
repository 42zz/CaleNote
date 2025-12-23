import SwiftUI
import SwiftData

struct CalendarSelectionOnboardingView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CachedCalendar.summary, order: .forward)
    private var calendars: [CachedCalendar]

    @State private var errorMessage: String?

    let onComplete: () -> Void

    private var calendarsPrimaryFirst: [CachedCalendar] {
        calendars.sorted { a, b in
            if a.isPrimary != b.isPrimary { return a.isPrimary && !b.isPrimary }
            return a.summary < b.summary
        }
    }

    private var hasEnabledCalendar: Bool {
        calendars.contains { $0.isEnabled }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("カレンダーを選択")
                    .font(.title)
                    .bold()

                Text("表示するカレンダーを選んでください\n（後から変更できます）")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 32)
            .onAppear {
                // 初期値設定: 有効なカレンダーがない場合はprimaryをONにする
                initializeDefaultSelection()
            }

            Divider()

            // カレンダー一覧
            List {
                ForEach(calendarsPrimaryFirst) { cal in
                    Toggle(
                        isOn: Binding(
                            get: { cal.isEnabled },
                            set: { newValue in
                                cal.isEnabled = newValue
                                cal.updatedAt = Date()
                                try? modelContext.save()
                                errorMessage = nil
                            }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cal.summary)
                                .font(.body)
                            if cal.isPrimary {
                                Text("メイン")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)

            Divider()

            // 下部ボタンエリア
            VStack(spacing: 12) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    completeOnboarding()
                } label: {
                    Text("続ける")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(hasEnabledCalendar ? Color.blue : Color.gray)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .disabled(!hasEnabledCalendar)
                .padding(.horizontal)

                if !hasEnabledCalendar {
                    Text("最低1つのカレンダーを選択してください")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 16)
        }
    }

    private func initializeDefaultSelection() {
        // 既に有効なカレンダーがある場合は何もしない
        if hasEnabledCalendar { return }

        // primaryカレンダーを自動的にONにする
        if let primary = calendars.first(where: { $0.isPrimary }) {
            primary.isEnabled = true
            primary.updatedAt = Date()
            try? modelContext.save()
        } else if let first = calendars.first {
            // primaryがない場合は最初のカレンダーをON
            first.isEnabled = true
            first.updatedAt = Date()
            try? modelContext.save()
        }
    }

    private func completeOnboarding() {
        // 書き込み先カレンダーが未設定なら自動設定
        let currentWriteCalendarId = JournalWriteSettings.loadWriteCalendarId()
        let enabledCalendars = calendars.filter { $0.isEnabled }

        if currentWriteCalendarId == nil || !enabledCalendars.contains(where: { $0.calendarId == currentWriteCalendarId }) {
            // ONになっているカレンダーの先頭（またはprimary）を設定
            if let primary = enabledCalendars.first(where: { $0.isPrimary }) {
                JournalWriteSettings.saveWriteCalendarId(primary.calendarId)
            } else if let first = enabledCalendars.first {
                JournalWriteSettings.saveWriteCalendarId(first.calendarId)
            }
        }

        // オンボーディング完了フラグを保存
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

        onComplete()
    }
}
