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

    // Googleカレンダーの標準色をベースにしたパレット（5x5 = 25色）
    // 参考: Google Calendar API colors (https://developers.google.com/calendar/api/v3/reference/colors)
    private let palette: [String] = [
        // 赤系
        "#d06b64", "#f83a22", "#fa573c",
        // オレンジ・黄色系
        "#ff7537", "#ffad46", "#fbd75b", "#fbe983",
        // 緑系
        "#42d692", "#16a765", "#7bd148", "#b3dc6c", "#51b749",
        // シアン・青系
        "#46d6db", "#4a86e8", "#a4bdfc", "#5484ed",
        // 紫系
        "#755aca", "#af38eb", "#dbadff", "#b99aff",
        // ピンク系
        "#f691b2",
        // 茶色・グレー系
        "#ac725e", "#e1e1e1",
        // ミントグリーン
        "#7ae7bf",
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

                            // 表示ONになった場合は長期キャッシュ取得を開始
                            if newValue {
                                ArchiveImportSettings.startBackgroundImport(
                                    for: calendar,
                                    auth: auth,
                                    modelContext: modelContext
                                )
                            }

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
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 50), spacing: 12)
                ], spacing: 16) {
                    ForEach(palette, id: \.self) { hex in
                        let isSelected = calendar.userColorHex == hex
                        let color = Color(hex: hex) ?? .blue
                        
                        ZStack {
                            // カラーチップ
                            Circle()
                                .fill(color)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            isSelected ? Color.primary : Color.secondary.opacity(0.3),
                                            lineWidth: isSelected ? 3 : 1
                                        )
                                )
                            
                            // 選択中のチェックマーク
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                            }
                        }
                        .contentShape(Circle())
                        .onTapGesture {
                            calendar.userColorHex = hex
                            calendar.updatedAt = Date()
                            try? modelContext.save()
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            // Section("アイコン") {
            //     ScrollView(.horizontal, showsIndicators: false) {
            //         HStack(spacing: 16) {
            //             ForEach(iconNames, id: \.self) { iconName in
            //                 Button {
            //                     calendar.iconName = iconName
            //                     calendar.updatedAt = Date()
            //                     try? modelContext.save()
            //                 } label: {
            //                     VStack(spacing: 8) {
            //                         ZStack {
            //                             Circle()
            //                                 .fill(
            //                                     Color(hex: calendar.userColorHex)?.opacity(0.2)
            //                                         ?? .blue.opacity(0.2)
            //                                 )
            //                                 .frame(width: 50, height: 50)

            //                             Image(systemName: iconName)
            //                                 .font(.title3)
            //                                 .foregroundStyle(
            //                                     Color(hex: calendar.userColorHex) ?? .blue)
            //                         }

            //                         if calendar.iconName == iconName {
            //                             Image(systemName: "checkmark.circle.fill")
            //                                 .foregroundStyle(.blue)
            //                                 .font(.caption)
            //                         } else {
            //                             Circle()
            //                                 .fill(Color.clear)
            //                                 .frame(width: 16, height: 16)
            //                         }
            //                     }
            //                 }
            //                 .buttonStyle(.plain)
            //             }
            //         }
            //         .padding(.horizontal, 4)
            //     }
            // }
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
}
