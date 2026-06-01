# App Store Screenshots Automation

Automated screenshot generation for Poplur2025 using Fastlane Snapshot.

## Setup

### 1. Install Fastlane

```bash
# Using Homebrew (recommended)
brew install fastlane

# Or using RubyGems
sudo gem install fastlane
```

### 2. Install Snapshot Dependencies

```bash
cd /path/to/Poplur2025
fastlane snapshot init
```

### 3. Configure Your App

Add the following to your app initialization (e.g., in `App.swift` or `SceneDelegate.swift`):

```swift
import SwiftUI

@main
struct Poplur2025App: App {
    
    init() {
        // Configure for screenshots if needed
        ScreenshotConfiguration.configure()
        
        if ScreenshotConfiguration.shouldUseDemoData {
            DemoDataManager.setupForScreenshots()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Skip onboarding in screenshot mode
                    if ScreenshotConfiguration.shouldSkipOnboarding {
                        // Navigate directly to main app
                    }
                }
        }
    }
}
```

### 4. Create UI Test Target

If you don't already have a UI test target:

1. In Xcode: File → New → Target
2. Choose "UI Testing Bundle"
3. Name it "Poplur2025UITests"
4. Add the `SnapshotUITests.swift` file to this target

### 5. Add Snapshot Helper (Bridging)

Create or update `Poplur2025UITests/Poplur2025UITests-Bridging-Header.h`:

```objc
#import "SnapshotHelper.h"
```

Then run:

```bash
fastlane snapshot init
```

This will generate the `SnapshotHelper.swift` file automatically.

## Usage

### Generate Screenshots

```bash
# Basic usage - generates screenshots for all configured devices
fastlane screenshots

# With device frames (requires frameit setup)
fastlane screenshots_framed

# Upload to App Store Connect
fastlane upload_screenshots

# Complete workflow (generate + upload)
fastlane screenshots_complete
```

### Test Specific Devices

Edit `fastlane/Snapfile` to customize devices:

```ruby
devices([
  "iPhone 15 Pro Max",
  "iPad Pro (12.9-inch) (6th generation)"
])
```

### Test Specific Languages

Edit `fastlane/Snapfile`:

```ruby
languages([
  "en-US",
  "es-ES",
  "fr-FR"
])
```

## Screenshot Locations

Screenshots are organized by device and language:

```
fastlane/screenshots/
├── en-US/
│   ├── iPhone 15 Pro Max/
│   │   ├── 01-MapView.png
│   │   ├── 02-FeedView.png
│   │   ├── 03-CameraView.png
│   │   ├── 04-ProfileView.png
│   │   └── 05-LocationSelection.png
│   └── iPad Pro (12.9-inch)/
│       └── ...
└── es-ES/
    └── ...
```

## Customization

### Add More Screenshots

Edit `Poplur2025UITests/SnapshotUITests.swift`:

```swift
func testGenerateAllScreenshots() throws {
    // Your custom screenshot logic
    takeScreenshot(name: "06-NewFeature")
}
```

### Change Screenshot Names

Rename in the test file:

```swift
takeScreenshot(name: "01-MapView") // Change this name
```

### Add Demo Data

Edit `Utilities/ScreenshotConfiguration.swift`:

```swift
static func createDemoPosts() -> [Post] {
    return [
        Post(username: "sarah_nyc", location: "Brooklyn", ...),
        Post(username: "mike_sf", location: "SF", ...),
    ]
}
```

## Troubleshooting

### Simulators Not Found

```bash
# List available simulators
xcrun simctl list devices available

# Delete and recreate simulators
xcrun simctl delete unavailable
```

### Build Failures

```bash
# Clean build folder
fastlane snapshot --clean

# Clear derived data
rm -rf ~/Library/Developer/Xcode/DerivedData
```

### Screenshots Not Saved

1. Check that `output_directory` exists in Snapfile
2. Ensure UI tests are passing: `cmd + U` in Xcode
3. Run with verbose logging: `fastlane snapshot --verbose`

### Status Bar Issues

Enable status bar override in Snapfile:

```ruby
override_status_bar(true)
```

## Device Frame Setup (Optional)

To add device frames around screenshots:

```bash
# Download device frames
fastlane frameit download_frames

# Apply frames
fastlane frameit
```

Or use the combined lane:

```bash
fastlane screenshots_framed
```

## CI/CD Integration

### GitHub Actions

Create `.github/workflows/screenshots.yml`:

```yaml
name: Generate Screenshots

on:
  workflow_dispatch:

jobs:
  screenshots:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Install Fastlane
        run: brew install fastlane
      - name: Generate Screenshots
        run: fastlane screenshots
      - name: Upload Artifacts
        uses: actions/upload-artifact@v4
        with:
          name: screenshots
          path: fastlane/screenshots/
```

## App Store Connect Requirements

### Required Screenshot Sizes

- **iPhone 6.7"** (iPhone 15 Pro Max): 1290 x 2796 px
- **iPad Pro 12.9"**: 2048 x 2732 px

### Optional Sizes

- **iPhone 6.1"** (iPhone 15 Pro): 1179 x 2556 px  
- **iPhone 5.5"**: 1242 x 2208 px
- **iPad Pro 11"**: 1668 x 2388 px

## Best Practices

1. **Use Demo Data**: Don't use real user data in screenshots
2. **Clean UI**: Remove notifications, popups, debug info
3. **Perfect Timing**: Use `sleep()` to wait for animations
4. **Status Bar**: Use `override_status_bar: true` for 9:41 AM
5. **Localization**: Test all supported languages
6. **Consistency**: Keep the same user flow across all screenshots
7. **Update Regularly**: Regenerate when UI changes

## Tips

- Run tests individually first to debug: `cmd + U` in Xcode
- Use accessibility identifiers for reliable element selection
- Take screenshots of your best features
- Show the app in use, not empty states
- Keep text readable - avoid tiny fonts
- Test on actual device sizes App Store Connect requires

## Support

- [Fastlane Documentation](https://docs.fastlane.tools/actions/snapshot/)
- [Snapshot Guide](https://docs.fastlane.tools/getting-started/ios/screenshots/)
- [App Store Screenshot Specifications](https://help.apple.com/app-store-connect/#/devd274dd925)
