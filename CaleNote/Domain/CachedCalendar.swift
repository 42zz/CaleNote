import Foundation
import SwiftData

@Model
final class CachedCalendar {
  @Attribute(.unique) var calendarId: String  // "primary" や実ID
  var summary: String
  var isPrimary: Bool

  // Google側の色IDなどを後で使うなら保持（任意）
  var googleColorId: String?

  // あなたの「ユーザーが選んだ表示色」
  var userColorHex: String

  // あなたの「ユーザーが選んだアイコン」
  var iconName: String

  // 表示ON/OFF（端末内だけ）
  var isEnabled: Bool

  var updatedAt: Date

  init(
    calendarId: String,
    summary: String,
    isPrimary: Bool,
    googleColorId: String? = nil,
    userColorHex: String = "#3B82F6",
    iconName: String = "calendar",
    isEnabled: Bool = false,
    updatedAt: Date = Date()
  ) {
    self.calendarId = calendarId
    self.summary = summary
    self.isPrimary = isPrimary
    self.googleColorId = googleColorId
    self.userColorHex = userColorHex
    self.iconName = iconName
    self.isEnabled = isEnabled
    self.updatedAt = updatedAt
  }
}
