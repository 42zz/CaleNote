# CI/CD Pipeline Documentation

This document describes the continuous integration and continuous deployment (CI/CD) pipeline for CaleNote.

## Overview

The CI/CD pipeline is implemented using GitHub Actions and provides automated testing, code quality checks, and release management.

## Workflows

### 1. SwiftLint (`.github/workflows/swiftlint.yml`)

**Trigger**: Pull requests and pushes to main branch

**Purpose**: Enforces code style and quality standards

**Actions**:
- Installs SwiftLint via Homebrew
- Runs SwiftLint with GitHub Actions logging reporter
- Reports violations directly in PR diffs

### 2. Build and Test (`.github/workflows/build-and-test.yml`)

**Trigger**: Pull requests and pushes to main branch

**Purpose**: Comprehensive testing and build verification

**Jobs**:

#### Unit Tests
- Runs all unit tests using `make test-unit`
- Uploads test results as artifacts
- Provides quick feedback on core functionality

#### UI Tests
- Runs all UI tests using `make test-ui`
- Captures screenshots for visual verification
- Uploads UI test results and screenshots

#### All Tests
- Runs complete test suite using `make test`
- Includes both unit and UI tests
- Uploads combined test results

#### Code Coverage
- Builds with code coverage enabled
- Runs tests with coverage instrumentation
- Generates coverage reports in JSON format
- Uploads coverage results for analysis

#### Build Verification
- Tests build on multiple simulator destinations:
  - iPhone 16 (latest iOS)
  - iPad Pro 11-inch (M4) (latest iOS)
- Ensures app builds correctly on different devices

### 3. Release (`.github/workflows/release.yml`)

**Trigger**: Git tags matching `v*.*.*` pattern

**Purpose**: Automated release management

**Jobs**:

#### Create Release
- Extracts version from git tag
- Generates release notes from CHANGELOG.md
- Creates GitHub Release with notes
- Marks release as official (not draft/prerelease)

#### Build Archive
- Builds app in Release configuration
- Creates xcarchive
- Exports IPA file
- Uploads archive as artifact

#### TestFlight Upload (Future)
- Disabled until App Store Connect is configured
- Will upload IPA to TestFlight for beta testing
- Requires Apple ID and app-specific password

### 4. Dependency Check (`.github/workflows/dependencies.yml`)

**Trigger**:
- Every Monday at 9:00 AM UTC
- Manual workflow dispatch

**Purpose**: Monitor dependencies and security

**Jobs**:

#### Check Swift Packages
- Resolves package dependencies
- Checks for outdated packages
- Generates dependency report
- Uploads report as artifact

#### Security Audit
- Runs TruffleHog to detect secret leaks
- Executes SwiftLint security rules
- Uploads security report

## Build Status Badges

Add these badges to your README.md:

```markdown
![Build Status](https://github.com/42zz/CaleNote/actions/workflows/build-and-test.yml/badge.svg)
![SwiftLint](https://github.com/42zz/CaleNote/actions/workflows/swiftlint.yml/badge.svg)
```

## Artifacts

All workflows upload artifacts for later inspection:

- **Test Results**: xcresult bundles from test runs
- **Coverage Reports**: JSON coverage data
- **Build Archives**: IPA files for releases
- **Dependency Reports**: Package dependency status
- **Security Reports**: Audit findings

Artifacts are retained for 90 days by default.

## Release Process

### Automated Release (Recommended)

1. Update CHANGELOG.md with release notes
2. Commit changes: `git commit -m "Release v1.0.0"`
3. Create annotated tag: `git tag -a v1.0.0 -m "Release v1.0.0"`
4. Push tag: `git push origin v1.0.0`
5. GitHub Actions will:
   - Build the release
   - Create GitHub Release with notes
   - Upload IPA artifact

### Manual Release

1. Follow automated release steps 1-4
2. Wait for GitHub Actions workflow to complete
3. Download IPA from workflow artifacts
4. Upload to App Store Connect or TestFlight manually

## Local Testing

Before pushing, test your changes locally:

```bash
# Run SwiftLint
make lint

# Build project
make build

# Run tests
make test

# Run specific test suites
make test-unit
make test-ui
```

## Troubleshooting

### Build Failures

- Check xcodebuild version compatibility
- Verify Xcode version in workflow matches local
- Ensure all dependencies are properly resolved

### Test Failures

- Download test result artifacts
- Open xcresult in Xcode for detailed logs
- Check for environment-specific issues (iOS version, simulator)

### SwiftLint Violations

- Review violations in PR diff comments
- Run `swiftlint --fix` to auto-fix some issues
- Update `.swiftlint.yml` if rules need adjustment

### Release Issues

- Verify git tag format matches `v*.*.*`
- Ensure CHANGELOG.md has Unreleased section
- Check export-options.plist configuration
- Verify Apple Developer credentials for TestFlight

## Configuration Files

- `.github/export-options.plist`: Archive export settings
- `.swiftlint.yml`: Code style rules
- `Makefile`: Build automation commands

## Security Considerations

- No secrets in workflow files
- Use GitHub Secrets for sensitive data
- TruffleHog scans for accidentally committed secrets
- Minimal permissions (only contents:write for releases)

## Future Enhancements

- [ ] TestFlight integration
- [ ] Automated App Store submission
- [ ] Beta distribution (TestFlight)
- [ ] Crash reporting integration
- [ ] Performance testing
- [ ] Screenshot capture for different screen sizes
- [ ] Automated changelog generation from commits
- [ ] Dependency update automation (Dependabot)

## Related Documentation

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Xcode Build Settings Reference](https://developer.apple.com/documentation/xcode/build-settings-reference)
- [SwiftLint Rules](https://github.com/realm/SwiftLint/blob/master/Rules.md)
