import ActivityKit
import Foundation

// Hem Runner (uygulama) hem PomodoroLiveActivity (widget extension)
// hedeflerinde derlenir. Veri, ActivityKit üzerinden uygulamadan extension'a
// taşınır; App Group gerekmez.
@available(iOS 16.1, *)
struct PomodoroAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    // false = Odaklanma, true = Kısa Mola
    var isBreak: Bool
    // true: sayaç iOS'un yerel zamanlayıcısıyla ilerliyor (endDate'e kadar)
    // false: duraklatılmış, remainingSeconds sabit gösterilir
    var isRunning: Bool
    var endDate: Date
    var startDate: Date
    var remainingSeconds: Int
    var totalSeconds: Int
  }

  var name: String
}
