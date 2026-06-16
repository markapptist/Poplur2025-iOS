import SwiftUI

/// Example integration showing how to use PopularPhone in your app
/// This demonstrates the complete setup for the phone calling feature

// MARK: - Quick Start Guide

/*
 
 # PopularPhone Integration
 
 ## What's Included:
 
 1. **PopularPhone.swift** - The main phone view with SpriteKit integration
 2. **PhoneScene.swift** - SpriteKit scene managing the phone visuals and interactions
 3. **DTMFToneGenerator.swift** - Utility to generate dial tone sounds
 4. **Updated DMsListView.swift** - Now includes phone call buttons
 
 ## How It Works:
 
 Each chat thread in the DMs list now has a green phone button. When tapped:
 - Opens the PopularPhone view as a sheet
 - Shows an animated phone with screen display
 - Dial pad buttons play DTMF tones and provide haptic feedback
 - Red hang-up button dismisses the call
 
 ## Setup Steps:
 
 ### Step 1: Add Screen Animation Assets
 
 1. Open your Asset Catalog (Assets.xcassets)
 2. Right-click → New Sprite Atlas
 3. Name it "screens"
 4. Add your screen animation frames (PNG images)
 5. Name them sequentially (screen_01, screen_02, etc.)
 
 Recommended frame size: 240x160 points (@2x = 480x320 pixels)
 
 ### Step 2: Add Dial Tone Sounds (Optional)
 
 Option A - Use Generated Tones:
 ```swift
 // Add this to your app's startup or a setup button
 DTMFToneGenerator.generateAllTones()
 
 // This creates WAV files in Documents directory
 // Copy them to your Xcode project from:
 // Settings → Storage → Files → [Your App]
 ```
 
 Option B - Add Custom Sound Files:
 - Add audio files to your project
 - Name them: dial_1.wav, dial_2.wav, ..., dial_9.wav, dial_0.wav, dial_star.wav, dial_hash.wav
 - Supported formats: WAV, MP3, M4A
 
 ### Step 3: Test the Integration
 
 Run your app and:
 1. Navigate to the Chats screen
 2. Tap the green phone icon next to any user
 3. Try tapping dial pad buttons
 4. Verify haptic feedback and sounds work
 5. Tap hang-up to dismiss
 
 ## Customization Examples:
 
 ### Change Phone Appearance:
 
 In PhoneScene.swift, modify the setupPhone() method:
 
 ```swift
 // Make phone bigger
 let phoneWidth: CGFloat = 320
 let phoneHeight: CGFloat = 480
 
 // Change phone color
 borderNode.fillColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0) // Darker
 
 // Adjust dial pad button colors
 circle.fillColor = UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0) // Blue buttons
 ```
 
 ### Add Call Duration Timer:
 
 In PopularPhone.swift:
 
 ```swift
 @State private var callDuration: TimeInterval = 0
 @State private var callTimer: Timer?
 
 var body: some View {
     // ... existing code ...
     
     Text(formatDuration(callDuration))
         .font(.title2)
         .foregroundColor(.white.opacity(0.8))
         .padding(.top, 8)
 }
 
 .onAppear {
     callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
         callDuration += 1
     }
 }
 
 .onDisappear {
     callTimer?.invalidate()
 }
 
 private func formatDuration(_ duration: TimeInterval) -> String {
     let minutes = Int(duration) / 60
     let seconds = Int(duration) % 60
     return String(format: "%02d:%02d", minutes, seconds)
 }
 ```
 
 ### Add Recent Calls List:
 
 Create a new model:
 
 ```swift
 struct CallRecord: Identifiable {
     let id = UUID()
     let user: FakeUser
     let timestamp: Date
     let duration: TimeInterval
     let type: CallType
     
     enum CallType {
         case outgoing
         case incoming
         case missed
     }
 }
 
 @MainActor
 class CallHistoryStore: ObservableObject {
     @Published var calls: [CallRecord] = []
     
     func addCall(_ call: CallRecord) {
         calls.insert(call, at: 0)
     }
 }
 ```
 
 Then inject it into PopularPhone:
 
 ```swift
 struct PopularPhone: View {
     let user: FakeUser
     @EnvironmentObject var callHistory: CallHistoryStore
     
     // ... existing code ...
     
     .onDisappear {
         phoneScene.stopAllSounds()
         
         // Record the call
         let record = CallRecord(
             user: user,
             timestamp: Date(),
             duration: callDuration,
             type: .outgoing
         )
         callHistory.addCall(record)
     }
 }
 ```
 
 ## Advanced Features:
 
 ### Real Phone Call Integration (iOS only):
 
 ```swift
 import CallKit
 
 // Implement CXProvider and CXCallController
 // This allows integration with the system's call UI
 // See Apple's CallKit documentation for full implementation
 ```
 
 ### Video Call Mode:
 
 ```swift
 enum CallMode {
     case audio
     case video
 }
 
 @State private var callMode: CallMode = .audio
 
 // Add toggle button in phone UI
 Button(action: { callMode = .video }) {
     Image(systemName: callMode == .audio ? "video" : "video.fill")
 }
 ```
 
 ### Speaker/Mute Controls:
 
 ```swift
 @State private var isMuted = false
 @State private var isSpeakerOn = false
 
 HStack(spacing: 40) {
     Button(action: { isMuted.toggle() }) {
         Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
     }
     
     Button(action: { isSpeakerOn.toggle() }) {
         Image(systemName: isSpeakerOn ? "speaker.wave.3.fill" : "speaker.fill")
     }
 }
 ```
 
 ## Troubleshooting:
 
 ### Phone doesn't appear:
 - Check that showPhoneCall state is being set correctly
 - Verify callingUser is not nil
 - Ensure sheet presentation works in your navigation setup
 
 ### No screen animation:
 - Verify "screens" atlas exists in Assets.xcassets
 - Check frame naming is sequential
 - Look for console errors about missing textures
 - Fallback placeholder should appear if atlas is missing
 
 ### No sound:
 - Check device volume
 - Verify device is not in silent mode
 - Ensure audio files are added to target
 - Haptic feedback should still work without audio
 
 ### Dial pad buttons not responding:
 - Check touch detection in PhoneScene
 - Verify button nodes have correct names
 - Look for console logs about button presses
 
 ## Performance Tips:
 
 1. **Optimize sprite atlas**: Use compressed PNG textures
 2. **Limit animation frames**: 10-20 frames is usually sufficient
 3. **Audio format**: WAV or M4A for best compatibility
 4. **Preload textures**: Scene loads textures on didMove(to:)
 5. **Memory management**: Audio players are cleaned up automatically
 
 ## Next Steps:
 
 - Customize phone appearance to match your app's design
 - Add call history tracking
 - Implement real calling with CallKit
 - Add video call support with AVFoundation
 - Create favorites/quick dial
 - Add contact search while in call
 
 */

// MARK: - Example Usage

struct PopularPhoneExample: View {
    @StateObject private var chatStore = FakeChatStore()
    @StateObject private var callHistory = CallHistoryStore()
    
    var body: some View {
        TabView {
            ChatThreadListView(chatStore: chatStore)
                .environmentObject(callHistory)
                .tabItem {
                    Label("Chats", systemImage: "message.fill")
                }
            
            CallHistoryView()
                .environmentObject(callHistory)
                .tabItem {
                    Label("Recents", systemImage: "clock.fill")
                }
        }
    }
}

// MARK: - Call History Example

@MainActor
class CallHistoryStore: ObservableObject {
    @Published var calls: [CallRecord] = []
    
    func addCall(_ call: CallRecord) {
        calls.insert(call, at: 0)
    }
}

struct CallRecord: Identifiable {
    let id = UUID()
    let user: FakeUser
    let timestamp: Date
    let duration: TimeInterval
    let type: CallType
    
    enum CallType {
        case outgoing
        case incoming
        case missed
        
        var icon: String {
            switch self {
            case .outgoing: return "phone.arrow.up.right.fill"
            case .incoming: return "phone.arrow.down.left.fill"
            case .missed: return "phone.down.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .outgoing: return .green
            case .incoming: return .blue
            case .missed: return .red
            }
        }
    }
}

struct CallHistoryView: View {
    @EnvironmentObject var callHistory: CallHistoryStore
    
    var body: some View {
        NavigationStack {
            List(callHistory.calls) { call in
                HStack {
                    Image(systemName: call.type.icon)
                        .foregroundColor(call.type.color)
                        .frame(width: 30)
                    
                    VStack(alignment: .leading) {
                        Text(call.user.name)
                            .font(.headline)
                        Text(formatTimestamp(call.timestamp))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if call.duration > 0 {
                        Text(formatDuration(call.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Recent Calls")
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview("Chat List with Phone") {
    PopularPhoneExample()
}

#Preview("Single Phone Call") {
    PopularPhone(user: FakeUser(id: UUID(), name: "Bob Smith"))
}
