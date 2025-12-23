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
    .navigationTitle("色を選択")
  }
}
