import Dependencies
import Foundation
import SQLiteData

/// How often a Care Task repeats, e.g. every 3 months.
public struct CareInterval: Hashable, Sendable {
  public enum Unit: String, CaseIterable, QueryBindable, Sendable {
    case week, month, year
  }

  public var count: Int
  public var unit: Unit

  public init(count: Int, unit: Unit) {
    self.count = count
    self.unit = unit
  }

  func date(after date: Date, calendar: Calendar) -> Date {
    let component: Calendar.Component =
      switch unit {
      case .week: .weekOfYear
      case .month: .month
      case .year: .year
      }
    return calendar.date(byAdding: component, value: count, to: date)!
  }
}

/// A one-off or recurring health obligation for a Cat, such as a vaccine or deworming.
@Table
public nonisolated struct CareTask: Hashable, Identifiable, Sendable {
  public let id: UUID
  public var catID: Cat.ID
  public var title: String
  /// Set by hand, e.g. the booster date on the vet card, or moved on when a recurring task is done.
  public var dueDate: Date
  public var repeatCount: Int?
  public var repeatUnit: CareInterval.Unit?
  /// When the due date was last set: added, changed by hand or moved on by a Care Record. Reminders whose time had
  /// passed by then never went out.
  public var dueDateSetAt: Date?

  /// Nil for a one-off task.
  public var interval: CareInterval? {
    get { repeatCount.flatMap { count in repeatUnit.map { CareInterval(count: count, unit: $0) } } }
    set {
      repeatCount = newValue?.count
      repeatUnit = newValue?.unit
    }
  }

  /// A title, and a repeat, if any, of at least one week, month or year.
  public static func isValid(title: String, interval: CareInterval?) -> Bool {
    !title.trimmingCharacters(in: .whitespaces).isEmpty && (interval?.count ?? 1) > 0
  }
}

public struct InvalidCareTask: Error {}

extension CareTask {
  public struct Preset: Hashable, Sendable {
    public var title: String
    public var interval: CareInterval
  }

  /// Suggestions only: every field stays editable, and the vet's schedule wins.
  public static let presets = [
    Preset(title: "Vaccine", interval: CareInterval(count: 1, unit: .year)),
    Preset(title: "Deworming", interval: CareInterval(count: 3, unit: .month)),
    Preset(title: "Flea treatment", interval: CareInterval(count: 1, unit: .month)),
    Preset(title: "Checkup", interval: CareInterval(count: 1, unit: .year)),
  ]
}

/// The dated record of a Care Task being done.
@Table
public nonisolated struct CareRecord: Hashable, Identifiable, Sendable {
  public let id: UUID
  public var careTaskID: CareTask.ID
  public var date: Date
  public var notes: String
  public var photo: Data?
}

extension CareRecord {
  /// The Cat's Care Records, newest first.
  public static func history(for catID: Cat.ID) -> some SelectStatementOf<CareRecord> {
    CareRecord.where { $0.careTaskID.in(CareTask.where { $0.catID.eq(catID) }.select(\.id)) }
      .order { $0.date.desc() }
  }
}

/// A Care Task with where it stands today.
public struct CareTaskStatus: Equatable, Identifiable, Sendable {
  public enum State: Equatable, Sendable {
    case overdue
    /// Due within the next week, or today.
    case dueSoon
    case later
    /// A one-off task with a Care Record.
    case done
  }

  public var task: CareTask
  public var state: State
  public var id: CareTask.ID { task.id }
  /// Shown on Today.
  public var isDue: Bool { state == .overdue || state == .dueSoon }

  /// Days ahead a Care Task counts as due soon.
  public static let dueSoonDays = 7
}

extension Database {
  @discardableResult
  public func addCareTask(for catID: Cat.ID, title: String, dueDate: Date, interval: CareInterval?) throws -> CareTask {
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now
    var task = CareTask(id: uuid(), catID: catID, title: title, dueDate: dueDate, dueDateSetAt: now)
    task.interval = interval
    guard CareTask.isValid(title: task.title, interval: task.interval) else { throw InvalidCareTask() }
    try CareTask.insert { task }.execute(self)
    return task
  }

  /// Saves a changed title, repeat or due date, e.g. the booster date from the vet card.
  public func updateCareTask(_ task: CareTask) throws {
    guard CareTask.isValid(title: task.title, interval: task.interval) else { throw InvalidCareTask() }
    guard let old = try CareTask.find(task.id).fetchOne(self) else { throw NotFound() }
    var task = task
    task.dueDateSetAt = old.dueDateSetAt
    try saveCareTask(task, dueDateWas: old.dueDate)
  }

  /// Saves the task, noting when its due date changed.
  private func saveCareTask(_ task: CareTask, dueDateWas old: Date) throws {
    @Dependency(\.date.now) var now
    var task = task
    if task.dueDate != old { task.dueDateSetAt = now }
    try CareTask.update(task).execute(self)
  }

  /// Deletes the task and its Care Records.
  public func deleteCareTask(_ id: CareTask.ID) throws {
    try CareTask.find(id).delete().execute(self)
  }

  /// Records the task as done, possibly backdated. A recurring task is next due one interval after its latest Care Record.
  @discardableResult
  public func addCareRecord(for id: CareTask.ID, on date: Date, notes: String, photo: Data?) throws -> CareRecord {
    @Dependency(\.uuid) var uuid
    guard try CareTask.find(id).fetchCount(self) > 0 else { throw NotFound() }
    let latest = try latestCareRecordDate(of: id)
    let record = CareRecord(id: uuid(), careTaskID: id, date: date, notes: notes, photo: photo)
    try CareRecord.insert { record }.execute(self)
    try followLatestCareRecord(of: id, from: latest)
    return record
  }

  /// Saves a corrected date, notes or photo. The record stays with its Care Task.
  public func updateCareRecord(_ record: CareRecord) throws {
    guard let old = try CareRecord.find(record.id).fetchOne(self) else { throw NotFound() }
    var record = record
    record.careTaskID = old.careTaskID
    let latest = try latestCareRecordDate(of: old.careTaskID)
    try CareRecord.update(record).execute(self)
    try followLatestCareRecord(of: old.careTaskID, from: latest)
  }

  /// A recurring task falls back to the Care Record before. With none left, a due date counted from the deleted
  /// record goes back to that record's date, since the one set before it is gone; one set by hand since stays.
  /// A one-off task is no longer done.
  public func deleteCareRecord(_ id: CareRecord.ID) throws {
    @Dependency(\.calendar) var calendar
    guard let old = try CareRecord.find(id).fetchOne(self) else { return }
    let latest = try latestCareRecordDate(of: old.careTaskID)
    try CareRecord.find(id).delete().execute(self)
    try followLatestCareRecord(of: old.careTaskID, from: latest)
    guard try latestCareRecordDate(of: old.careTaskID) == nil, var task = try CareTask.find(old.careTaskID).fetchOne(self),
      let interval = task.interval, task.dueDate == interval.date(after: old.date, calendar: calendar)
    else { return }
    let was = task.dueDate
    task.dueDate = old.date
    try saveCareTask(task, dueDateWas: was)
  }

  private func latestCareRecordDate(of taskID: CareTask.ID) throws -> Date? {
    try CareRecord.where { $0.careTaskID.eq(taskID) }.select { $0.date.max() }.fetchOne(self) ?? nil
  }

  /// A recurring task whose latest Care Record changed is next due one interval after the new latest. One added or
  /// corrected before the latest, e.g. the shelter's dose, is history only and leaves a hand-set due date alone.
  private func followLatestCareRecord(of taskID: CareTask.ID, from before: Date?) throws {
    @Dependency(\.calendar) var calendar
    guard var task = try CareTask.find(taskID).fetchOne(self), let interval = task.interval,
      let latest = try latestCareRecordDate(of: taskID), latest != before
    else { return }
    let was = task.dueDate
    task.dueDate = interval.date(after: latest, calendar: calendar)
    try saveCareTask(task, dueDateWas: was)
  }

  /// The Cat's Care Tasks, soonest due first, as of today on the device's local calendar.
  public func careTasks(for catID: Cat.ID) throws -> [CareTaskStatus] {
    @Dependency(\.calendar) var calendar
    @Dependency(\.date.now) var now
    let today = calendar.startOfDay(for: now)
    let soon = calendar.date(byAdding: .day, value: CareTaskStatus.dueSoonDays, to: today)!
    let tasks = try CareTask.where { $0.catID.eq(catID) }.order(by: \.dueDate).fetchAll(self)
    let recorded = Set(try CareRecord.where { $0.careTaskID.in(tasks.map(\.id)) }.select(\.careTaskID).fetchAll(self))
    return tasks.map { task in
      let day = calendar.startOfDay(for: task.dueDate)
      let state: CareTaskStatus.State =
        task.interval == nil && recorded.contains(task.id) ? .done
        : day < today ? .overdue
        : day <= soon ? .dueSoon
        : .later
      return CareTaskStatus(task: task, state: state)
    }
  }
}
