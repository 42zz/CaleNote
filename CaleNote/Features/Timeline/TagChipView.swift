import SwiftUI

struct TagChipView: View {
  let text: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(text)
        .font(.subheadline)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }
    .buttonStyle(.plain)
    .background {
      Capsule()
        .fill(isSelected ? Color.primary.opacity(0.15) : Color.secondary.opacity(0.10))
    }
  }
}
