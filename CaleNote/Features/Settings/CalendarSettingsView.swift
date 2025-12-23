import SwiftData
import SwiftUI

struct CalendarSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: GoogleAuthService
    @Bindable var calendar: CachedCalendar

    // 全カレンダーを取得（表示トグルと書き込み先の判定に必要）
    @Query private var allCalendars: [CachedCalendar]

    // 現在の書き込み先カレンダーID
    @State private var writeCalendarId: String? = JournalWriteSettings.loadWriteCalendarId()

    // 長期キャッシュ取り込み関連
    @State private var isImportingArchive = false
    @State private var archiveProgressText: String?
    @State private var archiveTask: Task<Void, Never>?
    private let archiveSync = ArchiveSyncService()

    // 固定パレット
    private let palette: [String] = [
        "#3B82F6", "#22C55E", "#F97316", "#EF4444", "#A855F7",
        "#06B6D4", "#64748B", "#F59E0B", "#10B981", "#EC4899",
    ]

    // アイコン一覧
    private let iconNames: [String] = [
        "calendar", "calendar.badge.clock", "calendar.badge.exclamationmark",
        "calendar.badge.plus", "calendar.badge.minus", "calendar.badge.checkmark",
        "note.text", "book", "bookmark", "star", "heart", "tag",
        "bell", "bell.fill", "clock", "clock.fill", "flag", "flag.fill",
    ]

    var body: some View {
        Form {
            Section("カレンダー情報") {
                HStack {
                    Text("名前")
                    Spacer()
                    Text(calendar.summary)
                        .foregroundStyle(.secondary)
                }

                if calendar.isPrimary {
                    HStack {
                        Text("種類")
                        Spacer()
                        Text("メイン")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("表示設定") {
                Toggle(
                    "表示する",
                    isOn: Binding(
                        get: { calendar.isEnabled },
                        set: { newValue in
                            // 変更後の有効カレンダー数をチェック
                            let currentEnabledCount = allCalendars.filter { $0.isEnabled }.count
                            let willBeEnabledCount =
                                currentEnabledCount
                                + (newValue
                                    ? (calendar.isEnabled ? 0 : 1)
                                    : (calendar.isEnabled ? -1 : 0))

                            // 最後の一つをOFFにしようとした場合は拒否
                            if willBeEnabledCount == 0 {
                                return
                            }

                            // 変更前の書き込みカレンダーIDを保存
                            let previousWriteCalendarId =
                                writeCalendarId
                                ?? defaultWriteCalendarId(
                                    from: allCalendars.filter { $0.isEnabled })

                            // カレンダーの状態を更新
                            calendar.isEnabled = newValue
                            calendar.updatedAt = Date()
                            try? modelContext.save()

                            // 書き込みカレンダーが非表示になった場合は自動変更
                            let updatedEnabledCalendars = allCalendars.filter { $0.isEnabled }
                            if !updatedEnabledCalendars.contains(where: {
                                $0.calendarId == previousWriteCalendarId
                            }) {
                                let newWriteCalendarId = defaultWriteCalendarId(
                                    from: updatedEnabledCalendars)
                                writeCalendarId = newWriteCalendarId
                                JournalWriteSettings.saveWriteCalendarId(newWriteCalendarId)
                            }
                        }
                    ))
            }

            Section("書き込み先") {
                let enabledCalendars = allCalendars.filter { $0.isEnabled }

                if !calendar.isEnabled {
                    Text("表示をONにすると、書き込み先として設定できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if enabledCalendars.isEmpty {
                    Text("表示するカレンダーがありません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Toggle(
                        "デフォルトの書き込み先",
                        isOn: Binding(
                            get: {
                                let currentWriteCalendarId =
                                    writeCalendarId
                                    ?? defaultWriteCalendarId(from: enabledCalendars)
                                return calendar.calendarId == currentWriteCalendarId
                            },
                            set: { isDefault in
                                if isDefault {
                                    // このカレンダーをデフォルトの書き込み先に設定
                                    writeCalendarId = calendar.calendarId
                                    JournalWriteSettings.saveWriteCalendarId(calendar.calendarId)
                                } else {
                                    // 他の有効なカレンダーをデフォルトに設定
                                    let otherEnabledCalendars = enabledCalendars.filter {
                                        $0.calendarId != calendar.calendarId
                                    }
                                    if let newDefault = otherEnabledCalendars.first {
                                        writeCalendarId = newDefault.calendarId
                                        JournalWriteSettings.saveWriteCalendarId(
                                            newDefault.calendarId)
                                    }
                                }
                            }
                        ))
                }
            }

            Section("色") {
                ForEach(palette, id: \.self) { hex in
                    HStack(spacing: 12) {
                        // カラーチップ
                        Circle()
                            .fill(Color(hex: hex) ?? .blue)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )

                        // 色コード（参考用）
                        Text(hex)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        // 選択中のチェックマーク
                        if calendar.userColorHex == hex {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        calendar.userColorHex = hex
                        calendar.updatedAt = Date()
                        try? modelContext.save()
                    }
                }
            }

            Section("アイコン") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(iconNames, id: \.self) { iconName in
                            Button {
                                calendar.iconName = iconName
                                calendar.updatedAt = Date()
                                try? modelContext.save()
                            } label: {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                Color(hex: calendar.userColorHex)?.opacity(0.2)
                                                    ?? .blue.opacity(0.2)
                                            )
                                            .frame(width: 50, height: 50)

                                        Image(systemName: iconName)
                                            .font(.title3)
                                            .foregroundStyle(
                                                Color(hex: calendar.userColorHex) ?? .blue)
                                    }

                                    if calendar.iconName == iconName {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                            .font(.caption)
                                    } else {
                                        Circle()
                                            .fill(Color.clear)
                                            .frame(width: 16, height: 16)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }

            Section("長期キャッシュ") {
                if !isImportingArchive {
                    Button {
                        archiveTask = Task { await importArchive() }
                    } label: {
                        Text("長期キャッシュを取り込む")
                    }
                } else {
                    HStack {
                        Button("取り込み中…") {}
                            .disabled(true)
                        Spacer()
                        Button("キャンセル") {
                            cancelArchiveImport()
                        }
                        .foregroundStyle(.red)
                    }
                }

                if let archiveProgressText {
                    Text(archiveProgressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("過去の振り返り用にカレンダーイベントを端末に保存します。件数が多いと時間がかかります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(calendar.summary)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func defaultWriteCalendarId(from enabled: [CachedCalendar]) -> String {
        if let saved = writeCalendarId, enabled.contains(where: { $0.calendarId == saved }) {
            return saved
        }
        if let primary = enabled.first(where: { $0.isPrimary }) {
            return primary.calendarId
        }
        return enabled.first?.calendarId ?? ""
    }

    @MainActor
    private func importArchive() async {
        if isImportingArchive { return }
        isImportingArchive = true
        defer {
            isImportingArchive = false
            archiveTask = nil
        }

        do {
            try await archiveSync.importAllEventsToArchive(
                auth: auth,
                modelContext: modelContext,
                calendars: [calendar]  // このカレンダーのみ
            ) { p in
                Task { @MainActor in
                    archiveProgressText =
                        "進捗: \(p.fetchedRanges)/\(p.totalRanges)\n"
                        + "反映: \(p.upserted) / 削除: \(p.deleted)"
                }
            }

            archiveProgressText = "長期キャッシュ取り込み完了"
        } catch is CancellationError {
            archiveProgressText = "取り込みをキャンセルしました（進捗は保存されています）"
        } catch {
            archiveProgressText = "取り込み失敗: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func cancelArchiveImport() {
        archiveTask?.cancel()
        archiveTask = nil
    }
}
