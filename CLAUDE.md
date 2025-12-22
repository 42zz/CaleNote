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
- **JournalEntry**: User-created journal entries with sync metadata (`linkedCalendarId`, `linkedEventId`, `needsCalendarSync`)
- **CachedCalendarEvent**: Local cache of Google Calendar events with unique ID format `"calendarId:eventId"`
- **CachedCalendar**: Metadata for user's calendars (enabled state, custom colors)
- **TimelineItem**: Unified view representation for both journals and events

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
- `CalendarSyncService`: Syncs Google Calendar → local cache (CachedCalendarEvent)
- `JournalCalendarSyncService`: Syncs JournalEntry → Google Calendar events
- `CalendarToJournalSyncService`: Reflects calendar changes back to linked journals
- `CalendarListSyncService`: Fetches and caches user's calendar list
- `CalendarCacheCleaner`: Removes old cached events outside sync window
- `LongTermCalendarImporter`: (New) Long-term event import functionality

**State Management:**
- `CalendarSyncState`: Persists syncToken per calendar (UserDefaults)
- `JournalWriteSettings`: Target calendar for new journals
- `SyncSettings`: Configurable sync window (past/future days from today)
- `SyncRateLimiter`: Prevents API abuse (5-second minimum interval between syncs)

**Utilities:**
- `TagExtractor`: Parses hashtags from journal content (`#tag` format)
- `TagStats`: Tracks tag usage frequency and recency
- `MockCalendarEventProvider`: Test data generation

#### Features Layer (`/CaleNote/Features/`)
SwiftUI views organized by feature:

**Navigation:** Tab-based interface with two main tabs

1. **TimelineView** (Main Tab):
   - Displays merged timeline of journals and calendar events
   - Search and tag filtering
   - Manual sync trigger with status/error display
   - Groups items by date (reverse chronological)
   - Tag statistics for quick filtering

2. **SettingsView** (Settings Tab):
   - Google Sign-In/Out
   - Calendar management (enable/disable, color customization)
   - Journal write target calendar selection
   - Sync window configuration
   - Pending sync queue display

3. **JournalEditorView** (Modal):
   - Create/edit journal entries
   - Title, body content (with tag auto-complete hints)
   - Event date picker
   - Auto-triggers sync to Google Calendar on save

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

All database models are registered in the model container at app startup (see CaleNoteApp.swift:14-18).

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
