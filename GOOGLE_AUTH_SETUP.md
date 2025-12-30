# Google Authentication Setup Guide

This guide explains how to set up Google Sign-In authentication for CaleNote.

## Prerequisites

- Xcode 15.0 or later
- iOS 17.0 or later
- Google Cloud Platform account

## Step 1: Create Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Note your Project ID

## Step 2: Enable Google Calendar API

1. In Google Cloud Console, navigate to **APIs & Services** > **Library**
2. Search for "Google Calendar API"
3. Click **Enable**

## Step 3: Create OAuth 2.0 Credentials

### Create iOS OAuth Client ID

1. Navigate to **APIs & Services** > **Credentials**
2. Click **Create Credentials** > **OAuth client ID**
3. Select **iOS** as the application type
4. Enter the following:
   - **Name**: CaleNote iOS
   - **Bundle ID**: `m42zz.CaleNote` (or your bundle identifier)
5. Click **Create**
6. Copy the **Client ID** (format: `xxxxxx.apps.googleusercontent.com`)

## Step 4: Download GoogleService-Info.plist

1. In Google Cloud Console, navigate to **APIs & Services** > **Credentials**
2. Download the `GoogleService-Info.plist` file
3. Add it to your Xcode project:
   - Drag and drop into Xcode
   - Ensure "Copy items if needed" is checked
   - Add to the CaleNote target

**OR** manually add Client ID to Info.plist:

```xml
<key>GIDClientID</key>
<string>YOUR_CLIENT_ID_HERE.apps.googleusercontent.com</string>
```

## Step 5: Configure URL Scheme

1. Open `Info.plist` in Xcode
2. Add a new URL Type:
   - **Identifier**: `com.googleusercontent.apps.YOUR_CLIENT_ID`
   - **URL Schemes**: Your reversed client ID

Example:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.123456789012-abcdefghijklmnopqrstuvwxyz012345</string>
        </array>
    </dict>
</array>
```

## Step 6: Update AppDelegate (if needed)

The Google Sign-In SDK handles URL callbacks automatically in SwiftUI apps.
No additional AppDelegate configuration is required for iOS 17+.

## Step 7: Test Authentication

1. Build and run the app
2. Tap "Sign in with Google"
3. Select your Google account
4. Grant calendar permissions
5. Verify you're signed in

## Troubleshooting

### "Client ID not found" error
- Verify `GoogleService-Info.plist` is added to the project
- Check that the Client ID matches your Google Cloud Console settings
- Ensure the file is included in the CaleNote target

### "Redirect URI mismatch" error
- Verify the URL scheme in Info.plist matches your reversed Client ID
- Check that the bundle identifier matches the one in Google Cloud Console

### "Calendar permissions not granted"
- Ensure Google Calendar API is enabled in Google Cloud Console
- Verify the requested scopes in `GoogleAuthService.swift`:
  - `https://www.googleapis.com/auth/calendar`
  - `https://www.googleapis.com/auth/calendar.events`

## Security Notes

- **Never commit** `GoogleService-Info.plist` to version control
- Add it to `.gitignore`:
  ```
  GoogleService-Info.plist
  ```
- For production, use environment-specific configurations
- Rotate credentials periodically

## References

- [Google Sign-In iOS Documentation](https://developers.google.com/identity/sign-in/ios)
- [Google Calendar API Documentation](https://developers.google.com/calendar/api)
- [OAuth 2.0 for Mobile Apps](https://developers.google.com/identity/protocols/oauth2/native-app)
