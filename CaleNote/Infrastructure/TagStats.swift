import Foundation

struct TagStat: Identifiable {
  let id: String
  let tag: String
  var count: Int
  var lastUsedAt: Date
}
