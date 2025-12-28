# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Google Sign-In authentication service (#2)
  - OAuth 2.0 integration with Google Sign-In SDK 9.0
  - Automatic token refresh with expiration check
  - Keychain-based session persistence
  - Calendar API scopes support
  - User profile information access (email, name, image)
  - Additional scopes request capability
  - Comprehensive setup documentation (GOOGLE_AUTH_SETUP.md)
- Error handling infrastructure (dependency for #2)
  - Custom error types for better error management
  - Retry policy with exponential backoff
  - Centralized error handler service
