import SwiftUI
import SwiftData

struct CalendarSelectionOnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: GoogleAuthService

    @Query(sort: \CachedCalendar.summary, order: .forward)
    private var calendars: [CachedCalendar]

    @State private var errorMessage: String?
    @State private var isLoadingCalendars = true  // 初期状態をローディングにする
    @State private var showRetryButton = false

    let onBack: () -> Void
    let onComplete: () -> Void

    private let listSync = CalendarListSyncService()

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
            // 戻るボタン
            HStack {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("戻る")
                    }
                    .font(.body)
                    .foregroundStyle(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }

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
            .task {
                // まずデータベースから直接確認
                let descriptor = FetchDescriptor<CachedCalendar>(
                    sortBy: [SortDescriptor(\.summary, order: .forward)]
                )
                var dbCalendars = (try? modelContext.fetch(descriptor)) ?? []
                
                // データベースにカレンダーがない場合は再同期を試みる
                if dbCalendars.isEmpty {
                    await reloadCalendars()
                } else {
                    // データベースにカレンダーがある場合は@Queryの更新を待つ
                    // まず、データベースから直接取得したカレンダーで初期値を設定
                    if !dbCalendars.contains(where: { $0.isEnabled }) {
                        if let primary = dbCalendars.first(where: { $0.isPrimary }) {
                            primary.isEnabled = true
                            primary.updatedAt = Date()
                        } else if let first = dbCalendars.first {
                            first.isEnabled = true
                            first.updatedAt = Date()
                        }
                        try? modelContext.save()
                        modelContext.processPendingChanges()
                        
                        // 再度データベースから取得
                        dbCalendars = (try? modelContext.fetch(descriptor)) ?? []
                    }
                    
                    // @Queryが更新されるまで待つ（最大3秒）
                    var waitCount = 0
                    while calendars.isEmpty && waitCount < 30 {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                        waitCount += 1
                    }
                    
                    // @Queryが更新されたら初期値を設定
                    if !calendars.isEmpty {
                        isLoadingCalendars = false
                        await initializeDefaultSelectionAsync()
                    } else {
                        // @Queryが更新されない場合は、データベースから直接設定した値を使用
                        // この場合、calendarsは空だが、データベースにはカレンダーがある
                        isLoadingCalendars = false
                        // エラーメッセージを表示せず、再試行ボタンを表示
                        showRetryButton = true
                        errorMessage = "カレンダーが表示されませんでした。再試行してください。"
                    }
                }
            }

            Divider()

            // カレンダー一覧
            if isLoadingCalendars {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("カレンダーを読み込み中...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if calendarsPrimaryFirst.isEmpty {
                VStack {
                    Spacer()
                    Text("カレンダーが見つかりませんでした")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
            }

            Divider()

            // 下部ボタンエリア
            VStack(spacing: 12) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                if showRetryButton {
                    Button {
                        Task {
                            await reloadCalendars()
                        }
                    } label: {
                        Text("再試行")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
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

                if !hasEnabledCalendar && !showRetryButton {
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

    private func initializeDefaultSelectionAsync() async {
        // @Queryが更新されるまで少し待機
        var waitCount = 0
        while calendars.isEmpty && waitCount < 10 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            waitCount += 1
        }
        
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

        // 選択されたカレンダーの長期キャッシュ取得を開始
        for calendar in enabledCalendars {
            ArchiveImportSettings.startBackgroundImport(
                for: calendar,
                auth: auth,
                modelContext: modelContext
            )
        }

        // オンボーディング完了フラグを保存
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

        onComplete()
    }

    private func reloadCalendars() async {
        isLoadingCalendars = true
        errorMessage = nil
        showRetryButton = false

        do {
            try await listSync.syncCalendarList(
                auth: auth,
                modelContext: modelContext
            )

            // modelContextの保留中の変更を処理
            modelContext.processPendingChanges()

            // SwiftDataの@Queryが更新されるまで少し待機
            // データベースから直接取得して確認
            var waitCount = 0
            var fetchedCalendars: [CachedCalendar] = []
            while fetchedCalendars.isEmpty && waitCount < 30 {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                // データベースから直接取得
                let descriptor = FetchDescriptor<CachedCalendar>(
                    sortBy: [SortDescriptor(\.summary, order: .forward)]
                )
                fetchedCalendars = (try? modelContext.fetch(descriptor)) ?? []
                waitCount += 1
            }

            if fetchedCalendars.isEmpty {
                errorMessage = "カレンダーを取得できませんでした。もう一度お試しください。"
                isLoadingCalendars = false
                showRetryButton = true
            } else {
                // @Queryが更新されるまで少し待機（最大2秒）
                var waitCount = 0
                while calendars.isEmpty && waitCount < 20 {
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                    waitCount += 1
                }
                
                // まだ@Queryが更新されていない場合は、データベースから直接設定
                if calendars.isEmpty {
                    // データベースから直接取得したカレンダーで初期値を設定
                    if let primary = fetchedCalendars.first(where: { $0.isPrimary }) {
                        primary.isEnabled = true
                        primary.updatedAt = Date()
                    } else if let first = fetchedCalendars.first {
                        first.isEnabled = true
                        first.updatedAt = Date()
                    }
                    try? modelContext.save()
                    modelContext.processPendingChanges()
                    
                    // もう一度@Queryの更新を待つ
                    waitCount = 0
                    while calendars.isEmpty && waitCount < 10 {
                        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                        waitCount += 1
                    }
                }
                
                // 初期値設定: 有効なカレンダーがない場合はprimaryをONにする
                await initializeDefaultSelectionAsync()
                isLoadingCalendars = false
                showRetryButton = false
            }

        } catch {
            errorMessage = "カレンダーの読み込みに失敗しました: \(error.localizedDescription)"
            isLoadingCalendars = false
            showRetryButton = true
        }
    }
}
