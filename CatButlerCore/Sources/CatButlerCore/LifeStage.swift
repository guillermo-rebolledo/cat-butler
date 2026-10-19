import Foundation

/// A Cat's age band, derived from its birthdate. Changes at the start of the birthday, whatever time of day the birthdate holds.
public enum LifeStage: Sendable {
  case kitten, adult, senior

  public init(birthdate: Date, on date: Date, calendar: Calendar = .current) {
    let years = calendar.dateComponents([.year], from: calendar.startOfDay(for: birthdate), to: calendar.startOfDay(for: date)).year ?? 0
    switch years {
    case 10...: self = .senior
    case 1...: self = .adult
    default: self = .kitten
    }
  }
}
