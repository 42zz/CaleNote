# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Comprehensive error handling system (#16)
  - Custom error types (CaleNoteError, NetworkError, APIError, LocalDataError)
  - Retry policy with exponential backoff
  - RetryExecutor for automatic retry logic
  - ErrorHandler service for centralized error management
  - Localized error messages and recovery suggestions
  - Error logging with OSLog

## [0.27] - 2025-12-24
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- SwiftData ScheduleEntry model as the core data structure (#1)
  - Support for data source tracking (Google Calendar / CaleNote)
  - Sync status management (synced / pending / failed)
  - Tag support
  - Comprehensive metadata (creation time, update time, last sync time)
  - Helper methods for sync status updates and tag management
