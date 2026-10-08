# Building ChoscorUsage

Requirements: macOS 26 or later on Apple Silicon, Xcode 26 (26.5 is what CI uses).

## Run from Xcode

1. Open `ChoscorUsage.xcodeproj`. Xcode resolves the local package
   `Packages/ChoscorUsageKit` automatically; there are no remote dependencies.
2. Select the `ChoscorUsage` scheme and **My Mac**, then Run.
3. The app has no Dock icon or window. Look for the gauge in the menu bar.

Local builds use automatic signing with no team ("Sign to Run Locally"). Because the
signature changes between builds, macOS may ask again for Keychain access to each Claude
profile after you rebuild.

## Command line

```sh
xcodebuild -project ChoscorUsage.xcodeproj -scheme ChoscorUsage \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/ChoscorUsage.app
```

Package logic can be built and tested without Xcode's UI:

```sh
swift test --package-path Packages/ChoscorUsageKit
```

## Data locations

- Profiles, last good snapshots and notification dedupe state:
  `~/Library/Application Support/com.choscor.ChoscorUsage/`
- Preferences: the `com.choscor.ChoscorUsage` defaults domain.

Delete both to start over; the next launch runs profile discovery again.

## Not covered yet

Developer ID signing, notarization, a DMG, Sparkle updates and GitHub Releases are
deferred to a later release spec. Do not distribute local builds.
