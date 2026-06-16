# PopularPhone - Asset Setup Guide

## Overview
PopularPhone is a SpriteKit-based phone dialing interface that appears when calling users from the DMs list. It features an animated screen and dial tone sound effects.

## Required Assets

### 1. Screen Spritesheet Atlas
Create a sprite atlas named **"screens"** in your Xcode project:

1. In Xcode, right-click on your asset catalog (usually `Assets.xcassets`)
2. Select **New Sprite Atlas** and name it `screens`
3. Add your screen animation frames to this atlas
   - Name them sequentially (e.g., `screen_01`, `screen_02`, etc.)
   - The animation will cycle through all frames automatically
   - Recommended size: 240x160 points at @2x resolution (480x320 pixels)
   - Supported formats: PNG with transparency

**Example screen frames:**
- Static display with signal bars
- Incoming call animation
- Ringing effect
- Digital display effects
- Any custom animation you want to show on the phone screen

### 2. Dial Tone Sound Effects (Optional but Recommended)
Add dial tone audio files to your project:

1. In Xcode, add audio files to your project bundle
2. Name them: `dial_1.mp3`, `dial_2.mp3`, through `dial_9.mp3`, plus `dial_0.mp3`, `dial_star.mp3`, and `dial_hash.mp3`
3. Supported formats: MP3, M4A, or WAV
4. Recommended duration: 0.3-0.5 seconds per tone

**To generate DTMF tones:**
- You can use online DTMF tone generators
- Standard DTMF frequencies:
  - 1: 697 + 1209 Hz
  - 2: 697 + 1336 Hz
  - 3: 697 + 1477 Hz
  - 4: 770 + 1209 Hz
  - 5: 770 + 1336 Hz
  - 6: 770 + 1477 Hz
  - 7: 852 + 1209 Hz
  - 8: 852 + 1336 Hz
  - 9: 852 + 1477 Hz
  - *: 941 + 1209 Hz
  - 0: 941 + 1336 Hz
  - #: 941 + 1477 Hz

### 3. Enabling Audio in PhoneScene.swift
Once you've added the dial tone audio files, update the `playDialTone` method in `PhoneScene.swift`:

```swift
private func playDialTone(for digit: String) {
    // Generate and play DTMF-like tone
    #if os(iOS)
    import AudioToolbox
    
    // Use system sound for tactile feedback
    AudioServicesPlaySystemSound(1104)
    
    // Play actual dial tone audio file
    playAudioFile(named: "dial_\(digit)")
    #endif
    
    generateHapticFeedback()
}
```

## Fallback Behavior
If assets are not provided:

- **Screen Animation**: A pulsing blue gradient will be displayed as a placeholder
- **Dial Tones**: Haptic feedback and system sounds will be used instead

## Implementation Details

### How It Works
1. User taps the phone icon next to any contact in the DMs list
2. `PopularPhone` view appears as a sheet presentation
3. The SpriteKit scene (`PhoneScene`) renders:
   - A phone chassis with rounded corners
   - An animated screen area cycling through spritesheet frames
   - A 4x3 dial pad (1-9, *, 0, #)
4. Tapping dial pad buttons triggers:
   - Visual scale animation
   - Haptic feedback
   - Dial tone sound (if audio files are present)
5. Tap the red hang-up button to dismiss

### Customization Options

**Phone Appearance** (in `PhoneScene.swift`):
```swift
// Adjust phone size
let phoneWidth: CGFloat = 280
let phoneHeight: CGFloat = 420

// Adjust colors
borderNode.fillColor = UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0)
```

**Screen Size**:
```swift
let screenWidth: CGFloat = 240
let screenHeight: CGFloat = 160
```

**Dial Pad Layout**:
```swift
let buttonSize: CGFloat = 60
let spacing: CGFloat = 15
```

## Testing
To test without assets:
1. Run the app
2. Navigate to the Chats/DMs screen
3. Tap the green phone icon next to any user
4. You should see the placeholder screen animation
5. Tap dial pad buttons to feel haptic feedback

## Future Enhancements
- Add actual phone call integration (CallKit)
- Record and display call history
- Add speaker/mute buttons
- Implement video call mode
- Add contact favorites quick-dial

## Troubleshooting

**Screen not animating:**
- Verify the sprite atlas is named exactly "screens"
- Check that frames are properly added to the atlas
- Look for console errors about missing textures

**No sound:**
- Ensure audio files are added to the target
- Check file names match exactly (case-sensitive)
- Verify audio format is supported
- Check device volume and silent mode

**Phone doesn't appear:**
- Verify `showPhoneCall` state is being set
- Check that `callingUser` is not nil
- Ensure sheet presentation is working correctly
