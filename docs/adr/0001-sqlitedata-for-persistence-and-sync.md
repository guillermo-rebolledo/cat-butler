# SQLiteData for persistence and CloudKit sync

Store data in SQLite through Point-Free's SQLiteData, not SwiftData. Households have to share data between different iCloud users. SwiftData can only sync a user's own private CloudKit database, even on iOS 26 and 27, so starting on SwiftData would force a rewrite of the storage layer once household sharing arrives. SQLiteData supports CloudKit private sync and sharing with other iCloud users out of the box, and plain SQL suits the reports we need, such as daily Intake and Missed Meals.

## Considered Options

- **SwiftData**: the obvious choice and first-party, but it has no shared-database sync.
- **Core Data with `NSPersistentCloudKitContainer`**: the most mature option for sharing, but its API is dated and its sync can't be inspected.
- **`CKSyncEngine` with our own store**: the most control, but we'd write the record mapping and the share flow ourselves.

## Consequences

We depend on a third-party library. The data model is designed around CloudKit sharing: the owner shares a record or zone, and each member has to accept the invite.

## Syncing a new table

Sync covers only the tables listed in `bootstrapDatabase()` in `CatButlerCore/Sources/CatButlerCore/Schema.swift`, so every new table must be added there in the same change that creates it. `SyncTests` fails until it is: give it a row of the new table. A new table or column also has to follow SQLiteData's rules for synced schemas (UUID primary keys, no uniqueness constraints, nullable or defaulted new columns), because older builds on the owner's other devices still sync with it.
