import SwiftData
import SwiftUI

struct CalendarColorPickerView: View {
  @Environment(\.modelContext) private var modelContext
  @Bindable var calendar: CachedCalendar

  // 固定パレット（あなたが後で調整する前提）
  private let palette: [String] = [
    "#3B82F6", "#22C55E", "#F97316", "#EF4444", "#A855F7",
    "#06B6D4", "#64748B", "#F59E0B", "#10B981", "#EC4899",
  ]

  var body: some View {
    List {
      ForEach(palette, id: \.self) { hex in
        HStack {
          Text(hex)
          Spacer()
          if calendar.userColorHex == hex {
            Image(systemName: "checkmark")
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
    .navigationTitle("色を選択")
  }
}
