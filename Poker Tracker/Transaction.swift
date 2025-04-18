import Foundation
import SwiftData

@Model
final class Transaction: Identifiable {
  @Attribute(.unique) var id: UUID = UUID()
  var amount: Int
  var date: Date
  var notes: String
  init(amount: Int, date: Date = .now) {
      self.amount = amount; self.date = date; self.notes = ""
  }
}
