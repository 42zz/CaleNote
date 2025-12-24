# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

### Building the Project
```bash
# Build the project
xcodebuild -scheme CaleNote -configuration Debug build

# Build for release
xcodebuild -scheme CaleNote -configuration Release build

# Clean build folder
xcodebuild -scheme CaleNote clean
```

### Running Tests
```bash
# Run all tests
xcodebuild -scheme CaleNote test

# Run unit tests only
xcodebuild -scheme CaleNote -only-testing:CaleNoteTests test

# Run UI tests only
xcodebuild -scheme CaleNote -only-testing:CaleNoteUITests test

# Run a specific test
xcodebuild -scheme CaleNote -only-testing:CaleNoteTests/TestClassName/testMethodName test
```

### Development
The project uses Xcode's standard iOS development workflow. Open `CaleNote.xcodeproj` in Xcode to run the app in the simulator or on a device.

## High-Level Architecture

### Core Concept
CaleNote is an iOS journaling app that treats **Google Calendar as the single source of truth**. Local SwiftData storage serves as the primary cache. Users write journal entries that synchronize bidirectionally with Google Calendar events.

### Layered Architecture

```
┌─────────────────────────────────────────┐
│         Features (SwiftUI Views)        │  ← User Interface Layer
├─────────────────────────────────────────┤
│     Infrastructure (Services)           │  ← Business Logic Layer
├─────────────────────────────────────────┤
│         Domain (Models)                 │  ← Data Models Layer
├─────────────────────────────────────────┤
│    SwiftData + Google Calendar API      │  ← Data Sources
└─────────────────────────────────────────┘
```

#### Domain Layer (`/CaleNote/Domain/`)
Core data models with SwiftData persistence:
- **JournalEntry**: User-created journal entries with sync metadata (`linkedCalendarId`, `linkedEventId`, `needsCalendarSync`) and conflict resolution fields (`hasConflict`, `conflictRemote*`)
- **CachedCalendarEvent**: Local cache of Google Calendar events with unique ID format `"calendarId:eventId"`
- **ArchivedCalendarEvent**: Long-term cache of events for historical browsing (2000-01-01 to future 1 year)
- **CachedCalendar**: Metadata for user's calendars (enabled state, custom colors)
- **TimelineItem**: Unified view representation for both journals and events with `isAllDay` flag for all-day event display
- **SyncLog**: Developer logging model for debugging sync operations (privacy-conscious: SHA256 hashed calendar IDs, no user content)

#### Infrastructure Layer (`/CaleNote/Infrastructure/`)
Business logic and external integrations:

**Authentication:**
- `GoogleAuthService`: OAuth flow, token management, scope handling

**API Client:**
- `GoogleCalendarClient`: Direct Google Calendar API calls
  - Handles incremental sync with `syncToken`
  - Event CRUD operations (`insertEvent`, `updateEvent`, `deleteEvent`)
  - Calendar list fetching
  - Date formatting (RFC3339, ISO8601)

**Synchronization Services:**
- `CalendarSyncService`: Syncs Google Calendar → local cache (CachedCalendarEvent), records sync logs
- `JournalCalendarSyncService`: Syncs JournalEntry → Google Calendar events, records sync logs
- `CalendarToJournalSyncService`: Reflects calendar changes back to linked journals, detects conflicts with 30-second tolerance
- `CalendarListSyncService`: Fetches and caches user's calendar list
- `CalendarCacheCleaner`: Removes old cached events outside sync window
- `ArchiveSyncService`: Long-term event import with cancellation support and progress persistence
- `ConflictResolutionService`: Resolves sync conflicts (useLocal/useRemote strategies)

**State Management:**
- `CalendarSyncState`: Persists syncToken per calendar (UserDefaults)
- `JournalWriteSettings`: Target calendar for new journals, event duration for calendar entries (default: 30 minutes)
- `SyncSettings`: Configurable sync window (past/future days from today)
- `SyncRateLimiter`: Prevents API abuse (5-second minimum interval between syncs)

**Utilities:**
- `TagExtractor`: Parses hashtags from journal content (`#tag` format)
- `TagStats`: Tracks tag usage frequency and recency
- `MockCalendarEventProvider`: Test data generation
- `SyncErrorReporter`: Reports sync failures to Crashlytics (failure type, calendar ID hash, HTTP code, 410 fallback status, sync phase)

#### Features Layer (`/CaleNote/Features/`)
SwiftUI views organized by feature:

**Navigation:** Tab-based interface with two main tabs

1. **TimelineView** (Main Tab):
   - Displays merged timeline of journals and calendar events
   - Search and tag filtering
   - Manual sync trigger with status/error display
   - Groups items by date (reverse chronological)
   - Tag statistics for quick filtering
   - Initial focus on "today" section with automatic scroll
   - Scroll up = future dates, scroll down = past dates
   - Empty section generation for today when no items exist
   - Auto-focus disabled during search
   - Date jump integration (selectedDayKey priority)

2. **SettingsView** (Settings Tab):
   - Google Sign-In/Out
   - Calendar management (enable/disable, color customization)
   - Journal write target calendar selection
   - Journal settings (event duration for calendar entries, configurable 1-480 minutes in 5-minute increments, default: 30 minutes)
   - Sync window configuration
   - Pending sync queue display
   - Long-term cache import with cancellation support
   - Hidden developer mode (7 taps on version to enable)

3. **Detail Views** (Unified Structure):
   - **JournalDetailView**: Displays journal entry details
   - **CalendarEventDetailView**: Displays cached calendar event details
   - **ArchivedCalendarEventDetailView**: Displays archived calendar event details
   - All three views share unified components:
     - `DetailHeaderView`: Title and date/time information
     - `DetailDescriptionSection`: Body text (tags removed) and tag list
     - `DetailMetadataSection`: Calendar name, sync status, last sync datetime, additional metadata (for archived events)
     - `RelatedMemoriesSection`: Related entries from past and future
   - Metadata display:
     - Sync status shows "最終同期: YYYY/MM/DD HH:mm" format (using `cachedAt` for events, `updatedAt` for journals temporarily)
     - Additional metadata rows for archived events (status, cache datetime, journal link, holiday ID)
   - Unified toolbar with edit button (consistent styling across all views)
   - Conflict resolution button shown in JournalDetailView when `hasConflict == true`

4. **JournalEditorView** (Modal):
   - Create/edit journal entries
   - Title, body content (with tag auto-complete hints)
   - Event date picker
   - Auto-triggers sync to Google Calendar on save
   - Event duration uses setting from JournalWriteSettings (default: 30 minutes)

5. **ConflictResolutionView** (Modal):
   - Side-by-side comparison of local vs calendar version
   - User selects which version to keep (useLocal/useRemote)
   - Triggered from JournalDetailView when conflict detected

6. **DeveloperToolsView** (Hidden):
   - Sync operation logs with timestamps and counts
   - Privacy-conscious: SHA256 hashed calendar IDs, no user content
   - JSON export for debugging
   - Log deletion functionality
   - Access: 7 taps on version in SettingsView

## Synchronization Architecture

### Bidirectional Sync Flow

**Journal → Calendar:**
```
User saves JournalEntry
  ↓
needsCalendarSync = true
  ↓
JournalCalendarSyncService.syncOne()
  ↓
GoogleCalendarClient.insertEvent() / updateEvent()
  ↓
JournalEntry stores linkedEventId and linkedCalendarId
```

**Calendar → Local Cache:**
```
User triggers sync (manual or auto)
  ↓
CalendarListSyncService.sync() (fetch calendar list)
  ↓
CalendarSyncService.syncOneCalendar() (for each enabled calendar)
  ↓
GoogleCalendarClient.listEvents(syncToken: previousToken)
  ↓
Apply changes to CachedCalendarEvent
  ↓
Store new syncToken for next incremental sync
```

**Calendar → Journal Reflection:**
```
Calendar event changes detected
  ↓
CalendarToJournalSyncService processes linked events
  ↓
Updates JournalEntry metadata (event cancelled, title changed, etc.)
```

### Incremental Sync Strategy
- Uses Google Calendar API `syncToken` for delta updates
- Falls back to full sync on token expiration (HTTP 410 GONE)
- Configurable sync window (X days past, Y days future from today)
- Rate limiting prevents excessive API calls (5-second cooldown)
- Sync state persisted per calendar in UserDefaults

### Event Linking Mechanism
- JournalEntry stores `linkedCalendarId` and `linkedEventId`
- Google Calendar events store `journalId` in extended properties
- Bidirectional reference enables sync conflict resolution

### Conflict Detection and Resolution
- **Detection**: When both local and calendar versions are updated
  - Requires `linkedEventUpdatedAt` to exist (already synced)
  - Local `updatedAt` > calendar `updatedAt`
  - Time difference > 30 seconds (prevents false positives from timestamp drift)
- **Resolution**: User chooses via ConflictResolutionView
  - **useLocal**: Re-sync local version to calendar (sets `needsCalendarSync = true`)
  - **useRemote**: Overwrite local with calendar version
- **Auto-clear**: Conflict flags cleared when remote changes successfully applied

## Key Design Patterns

1. **Service Locator:** Services instantiated in views and dependency-injected
2. **Environment Injection:** `GoogleAuthService` passed via `@EnvironmentObject`
3. **Async/Await:** All API calls and DB operations use Swift concurrency
4. **Predicate-Based Queries:** SwiftData `@Query` with dynamic filtering
5. **State Management:** `@State`, `@StateObject`, `@Published` for reactive UI

## Technology Stack

- **Framework:** SwiftUI (iOS 17.0+)
- **Persistence:** SwiftData (Apple's modern ORM)
- **Authentication:** Google Sign-In SDK (SPM dependency)
- **Networking:** URLSession (native)
- **Concurrency:** Swift async/await with strict concurrency checking enabled

## SwiftData Configuration

The app uses SwiftData with strict concurrency settings:
- `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`

All database models are registered in the model container at app startup (see CaleNoteApp.swift:14-20).

## Sync Logging for Developers

The app includes a comprehensive sync logging system for debugging and monitoring:

### SyncLog Model
- **Purpose**: Track all sync operations for debugging
- **Privacy**: Calendar IDs are SHA256 hashed (first 8 chars only), no user content recorded
- **Fields**:
  - `syncType`: "incremental", "full", "archive", "journal_push"
  - `calendarIdHash`: SHA256 hash of calendar ID (first 8 characters)
  - `updatedCount`, `deletedCount`, `skippedCount`, `conflictCount`: Result counts
  - `had410Fallback`: syncToken expired, fell back to full sync
  - `had429Retry`: Rate limit encountered
  - `httpStatusCode`, `errorType`, `errorMessage`: Error tracking
  - `timestamp`, `endTimestamp`: Duration tracking

### Logging Implementation
All sync services automatically record logs:
- **CalendarSyncService**: Logs incremental/full syncs, 410 fallback detection
- **JournalCalendarSyncService**: Logs journal push operations
- **ArchiveSyncService**: Logs long-term imports, includes cancellation tracking
- **CalendarToJournalSyncService**: Currently no direct logging (uses CalendarSyncService logs)

### Developer Tools Access
- Settings → Tap version 7 times → Developer Tools section appears
- View sync logs, export as JSON, delete all logs
- Useful for debugging sync issues without compromising user privacy

## Important Implementation Notes

### When Modifying Data Models
1. Update the domain model (`/Domain/`)
2. Consider migration strategy (SwiftData schema evolution)
3. Update related sync services in Infrastructure
4. Update UI components in Features

### When Adding API Functionality
1. Add methods to `GoogleCalendarClient`
2. Handle errors and edge cases (token expiration, network failures)
3. Update relevant sync services
4. Consider rate limiting implications

### When Adding UI Features
1. Create view in appropriate Features subfolder
2. Inject required services via `@EnvironmentObject` or `@StateObject`
3. Use `@Query` for SwiftData reads
4. Use `modelContext` for writes
5. Follow existing patterns for error handling and user feedback

### When Adding Sync Operations
1. Create `SyncLog` at the start of the operation
2. Set appropriate `syncType` ("incremental", "full", "archive", "journal_push")
3. Hash calendar ID using `SyncLog.hashCalendarId()` for privacy
4. Record counts (`updatedCount`, `deletedCount`, etc.)
5. Set `endTimestamp` when operation completes
6. Record errors with `errorType` and `errorMessage` on failure
7. Never record user content (titles, descriptions) in logs
8. Call `SyncErrorReporter.reportSyncFailure()` in catch blocks to send failures to Crashlytics
9. Extract HTTP status code using `SyncErrorReporter.extractHttpStatusCode()` and include in both `SyncLog` and Crashlytics report

### Testing Strategy
- Unit tests: Use `MockCalendarEventProvider` for test data
- Test targets: `CaleNoteTests` (unit), `CaleNoteUITests` (UI)
- Focus on sync logic and API error handling in tests

## Common Pitfalls to Avoid

1. **Don't bypass sync services:** Always use JournalCalendarSyncService to update Google Calendar
2. **Don't ignore needsCalendarSync flag:** Failed syncs should be retried
3. **Don't forget rate limiting:** Use SyncRateLimiter for user-triggered syncs
4. **Don't assume syncToken validity:** Always handle HTTP 410 GONE (token expired)
5. **Don't modify CachedCalendarEvent directly:** Only CalendarSyncService should write to this model
6. **Don't hardcode calendar IDs:** Always use user-selected target calendar from JournalWriteSettings

## Google Calendar API Configuration

- OAuth Client ID: `505927366776-2gu092vlu40cj9hg00b40rkdsm1m1vk7.apps.googleusercontent.com`
- Required scopes: Calendar read/write
- OAuth callback handled via custom URL scheme (configured in Info.plist)

## Documentation Update Policy

**IMPORTANT**: When making code changes, you MUST update the following documentation files:

### 1. CHANGELOG.md
Update this file **immediately** after implementing any feature or fix:
- Add entry under the current version number (or create new version section)
- Include: date, version, category (Added/Changed/Fixed/Removed)
- Describe what changed and why
- Reference affected files and services

### 2. README.md
Update when changes affect user-facing functionality or core architecture:
- Update relevant sections (機能要件, 画面構成, データモデル, etc.)
- Increment version number in 更新履歴
- Keep spec aligned with actual implementation (実装準拠)
- Document new UI screens, data models, or sync behaviors

### 3. CLAUDE.md (this file)
Update when changes affect development workflow or architecture:
- Add new services to Infrastructure layer descriptions
- Update Features layer when adding new views
- Add new models to Domain layer
- Update sync architecture if flow changes
- Add to "Common Pitfalls" if new gotchas emerge

### Update Checklist for New Features
When implementing a new feature, update in this order:
1. ✅ Write code
2. ✅ Test functionality
3. ✅ Update CHANGELOG.md (what changed)
4. ✅ Update README.md (user-facing spec)
5. ✅ Update CLAUDE.md (developer guidance)
6. ✅ Commit all changes together

**Why this matters**: These docs are the single source of truth for understanding the codebase. Outdated docs lead to confusion, bugs, and wasted developer time.
