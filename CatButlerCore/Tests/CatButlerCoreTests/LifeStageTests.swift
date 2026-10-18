import CatButlerCore
import Foundation
import Testing

struct LifeStageTests {
  let calendar = Calendar(identifier: .gregorian)
  let birthdate = Date(timeIntervalSince1970: 1_700_000_000)

  func age(years: Int = 0, months: Int = 0, days: Int = 0) -> Date {
    calendar.date(byAdding: DateComponents(year: years, month: months, day: days), to: birthdate)!
  }

  @Test func kittenUntilFirstBirthday() {
    #expect(LifeStage(birthdate: birthdate, on: birthdate, calendar: calendar) == .kitten)
    #expect(LifeStage(birthdate: birthdate, on: age(months: 12, days: -1), calendar: calendar) == .kitten)
  }

  @Test func adultFromTwelveMonths() {
    #expect(LifeStage(birthdate: birthdate, on: age(months: 12), calendar: calendar) == .adult)
    #expect(LifeStage(birthdate: birthdate, on: age(years: 10, days: -1), calendar: calendar) == .adult)
  }

  @Test func seniorFromTenthBirthday() {
    #expect(LifeStage(birthdate: birthdate, on: age(years: 10), calendar: calendar) == .senior)
  }
}
