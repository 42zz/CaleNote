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

### Linting
```bash
# Run SwiftLint manually
swiftlint --config .swiftlint.yml
```

### Development
The project uses Xcode's standard iOS development workflow. Open `CaleNote.xcodeproj` in Xcode to run the app in the simulator or on a device.

## High-Level Architecture

### Core Concept
CaleNote is an iOS app that treats **Google Calendar as the single source of truth (SSoT)**. The app allows users to create schedule entries (both events and journal entries) that synchronize bidirectionally with Google Calendar events. From a user experience perspective, events and journal entries are treated as a unified "schedule entry" concept.

### Design Principles

Based on APP_SPECIFICATION.md, the app follows these core principles:

1. **Google Calendar as SSoT**: Complete bidirectional synchronization with Google Calendar as the single source of truth
2. **Immediate UI Response**: Local-first updates with asynchronous synchronization
3. **Index-Driven Design**: Avoid raw data scanning, use dedicated indexes
4. **Zero Learning Curve**: UI and navigation should not require new concepts

### Target Architecture

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

## Data Model Design

### Schedule Entry (Core Concept)

The minimum data unit in CaleNote is a "Schedule Entry". From a user experience perspective, it's treated as a single unified concept without distinguishing between events and journal entries.

Internally, each schedule entry should maintain:

* `source` (google / calenote)
* `managedByCaleNote` (boolean)
* `googleEventId`
* `startAt` / `endAt`
* `isAllDay` (boolean) - for all-day events
* `title` / `body`
* `tags`
* `syncStatus` (synced / pending / failed)
* `lastSyncedAt`

### Google Calendar Event Mapping

All schedule entries correspond 1-to-1 with Google Calendar events. Entries created in CaleNote should include metadata identifying them as CaleNote-managed events when saved to Google Calendar.

Local data serves as cache for fast display, but the ultimate source of truth is always Google Calendar.

## Current Project State

**Status**: Reset to minimal structure (2025/12/30)

The project has been reset and is ready for fresh development. Current structure:

* **App Layer**: `CaleNoteApp.swift` - Minimal app entry point with `ContentView`
* **Features Layer**: `ContentView.swift` - Basic placeholder view
* **Domain Layer**: Empty (to be implemented)
* **Infrastructure Layer**: Empty (to be implemented)

## Implementation Guidelines

### When Creating Data Models

1. Create models in `/CaleNote/Domain/` directory
2. Use SwiftData for persistence
3. Follow the Schedule Entry data model specification above
4. Register models in `CaleNoteApp.swift` model container
5. Consider index requirements for search performance (200ms target for title/tag search)

### When Creating Services

1. Create services in `/CaleNote/Infrastructure/` directory
2. Organize by responsibility:
   - **Authentication**: Google Sign-In integration
   - **API Client**: Direct Google Calendar API calls
   - **Synchronization**: Bidirectional sync services
   - **Settings**: User settings, calendar configuration (e.g., CalendarSettings)
   - **State Management**: Sync state, error handling
   - **Utilities**: Tag extraction, search indexing, etc.
3. Use async/await for all API calls and DB operations
4. Implement proper error handling and retry logic
5. Consider rate limiting for API calls

### When Creating UI Views

1. Create views in `/CaleNote/Features/` directory
2. Organize by feature area (Timeline, Editor, Settings, etc.)
3. Follow Google Calendar app UI patterns as benchmark
4. Implement immediate local updates, then async sync
5. Show sync status indicators for pending/failed operations
6. Use SwiftUI `@Query` for SwiftData reads
7. Use `modelContext` for writes

### Synchronization Requirements

Based on APP_SPECIFICATION.md:

* **Immediate Local Updates**: App operations should reflect immediately in local database
* **Asynchronous Sync**: Google Calendar synchronization should happen in background
* **Bidirectional Sync**: Changes from Google Calendar should be reflected in app
* **Sync State Management**: Each entry should track sync status (synced/pending/failed)
* **Recovery**: Failed syncs should be retryable from timeline and settings
* **BackgroundTasks**: Use BGAppRefreshTask for periodic sync and BGProcessingTask for index rebuilds (see `Infrastructure/Sync/BackgroundTaskManager.swift`)

### Search Requirements

* **Performance Target**: Title prefix match and tag search must respond within 200ms
* **Index-Driven**: Use dedicated search index, avoid raw data scanning
* **Body Search**: Implement as staged/delayed execution, exclude from initial results

### Related Entries (振り返り)

When implementing entry detail views, include related entries from past and future:

* **Matching Criteria**:
  - Same month/day (MMDD match)
  - Same weekday in same week
  - Same holiday
* **Implementation**: Use dedicated Related Index, avoid raw searches

## Technology Stack

- **Framework:** SwiftUI (iOS 17.0+)
- **Persistence:** SwiftData (Apple's modern ORM)
- **Authentication:** Google Sign-In SDK (to be added)
- **Networking:** URLSession (native)
- **Concurrency:** Swift async/await with strict concurrency checking

## SwiftData Configuration

When implementing SwiftData:

* Enable strict concurrency settings:
- `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
* Register all models in the model container at app startup
* Use `@Query` for reads, `modelContext` for writes

## UI/UX Guidelines

Based on APP_SPECIFICATION.md:

* **Benchmark**: Google Calendar app's UI patterns and interaction flow
* **Navigation**: 
  - Top: Display toggle, month view, search, today focus
  - Left: Sidebar (calendar selection, settings, feedback)
  - Main: Vertical timeline
* **Timeline View**:
  - Group entries by date
  - Display entries in chronological order within each day
  - Mix Google Calendar events and CaleNote entries in same list
  - Show sync status badges for incomplete syncs
* **Entry Creation**: FAB (+) button in bottom right
* **Zero Learning Curve**: Don't introduce new concepts that require user learning

## Performance Requirements

* **Launch Time**: Initial display within 1 second (perceived)
* **Smooth Operation**: No frame drops during scroll/search
* **Data Recovery**: Local data corruption should be recoverable from Google Calendar

## Google Calendar API Integration

When implementing Google Calendar integration:

* **OAuth**: Use Google Sign-In SDK for authentication
* **Scopes**: Calendar read/write permissions
* **API Client**: Create `GoogleCalendarClient` for direct API calls
* **Sync Strategy**: 
  - Use incremental sync with `syncToken` when possible
  - Fall back to full sync on token expiration (HTTP 410)
  - Implement configurable sync window (X days past, Y days future)
* **Rate Limiting**: Implement rate limiting to prevent API abuse

## Key Design Patterns

1. **Service Locator**: Services instantiated in views and dependency-injected
2. **Environment Injection**: Pass services via `@EnvironmentObject` or `@StateObject`
3. **Async/Await**: All API calls and DB operations use Swift concurrency
4. **Predicate-Based Queries**: SwiftData `@Query` with dynamic filtering
5. **State Management**: `@State`, `@StateObject`, `@Published` for reactive UI

## Important Implementation Notes

### When Modifying Data Models
1. Update the domain model (`/Domain/`)
2. Consider migration strategy (SwiftData schema evolution)
3. Update related sync services in Infrastructure
4. Update UI components in Features

### When Adding API Functionality
1. Add methods to API client service
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
- Unit tests: Create mock providers for test data
- Test targets: `CaleNoteTests` (unit), `CaleNoteUITests` (UI)
- Focus on sync logic and API error handling in tests
- UI tests should launch with UI test arguments (`UI_TESTING`, `UI_TESTING_RESET`, `UI_TESTING_SEED`, `UI_TESTING_MOCK_AUTH`, `UI_TESTING_SKIP_SYNC`)
- Snapshot attachments are captured in UI tests for light/dark mode and orientation checks

## Common Pitfalls to Avoid

1. **Don't bypass sync services**: Always use proper sync services to update Google Calendar
2. **Don't ignore sync status**: Failed syncs should be retried
3. **Don't forget rate limiting**: Implement rate limiting for user-triggered syncs
4. **Don't assume syncToken validity**: Always handle HTTP 410 GONE (token expired)
5. **Don't scan raw data**: Use indexes for search operations
6. **Don't introduce new concepts**: Follow Google Calendar app patterns

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
- Keep spec aligned with actual implementation
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
