import SwiftUI
import SwiftData

struct CalendarPickerView: View {
    let calendars: [CachedCalendar]
    @Binding var selectedCalendarId: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if calendars.isEmpty {
                    Text("選択可能なカレンダーがありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(calendars) { calendar in
                        Button {
                            selectedCalendarId = calendar.calendarId
                            dismiss()
                        } label: {
                            HStack {
                                // カレンダーの色とアイコン
                                ZStack {
                                    Circle()
                                        .fill(calendarColor(for: calendar).opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    
                                    Image(systemName: calendar.iconName)
                                        .font(.caption)
                                        .foregroundStyle(calendarColor(for: calendar))
                                }
                                
                                Text(calendar.summary)
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                if selectedCalendarId == calendar.calendarId {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("書き込み先を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func calendarColor(for calendar: CachedCalendar) -> Color {
        if let hex = Color(hex: calendar.userColorHex) {
            return hex
        }
        return .blue
    }
}

