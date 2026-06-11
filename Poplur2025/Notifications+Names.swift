import Foundation

extension Notification.Name {
    // Feed, Map, and Profile loading
    static let LoadFeedNow = Notification.Name("LoadFeedNow")
    static let LoadMapNow = Notification.Name("LoadMapNow")
    static let LoadProfileNow = Notification.Name("LoadProfileNow")
    static let PlayFeedLaunchLogo = Notification.Name("PlayFeedLaunchLogo")
    
    // Tab and navigation
    static let ResetTabToTop = Notification.Name("ResetTabToTop")
    static let RecordTabBecameActive = Notification.Name("RecordTabBecameActive")
    static let ShowUserProfile = Notification.Name("ShowUserProfile")
    
    // Cube interactions
    static let CubeMotionUpdate = Notification.Name("CubeMotionUpdate")
    static let CubeGlobalDragChanged = Notification.Name("CubeGlobalDragChanged")
    static let CubeGlobalDragEnded = Notification.Name("CubeGlobalDragEnded")
    static let CubeGlobalTap = Notification.Name("CubeGlobalTap")
    static let cubeHoldBegan = Notification.Name("cubeHoldBegan")
    static let cubeHoldEnded = Notification.Name("cubeHoldEnded")
    static let cameraCubeHoldBegan = Notification.Name("cameraCubeHoldBegan")
    static let cameraCubeHoldEnded = Notification.Name("cameraCubeHoldEnded")
    static let cameraCubeTabViewTapped = Notification.Name("cameraCubeTabViewTapped")
    static let CubeStartFlashing = Notification.Name("CubeStartFlashing")
    static let CubeStopFlashing = Notification.Name("CubeStopFlashing")
    static let CenterMapOnUser = Notification.Name("CenterMapOnUser")
    
    // Feed and audio
    static let FeedReady = Notification.Name("FeedReady")
    static let PauseFeedAudio = Notification.Name("PauseFeedAudio")
    static let ResumeFeedAudio = Notification.Name("ResumeFeedAudio")
    static let PauseGlobalFeedAudio = Notification.Name("PauseGlobalFeedAudio")
    
    // Map and location
    static let CenterMapOnUserLocation = Notification.Name("CenterMapOnUserLocation")
    static let SharedRadiusDidChange = Notification.Name("SharedRadiusDidChange")
    static let MapSuggestedRadius = Notification.Name("MapSuggestedRadius")
    
    // Settings and UI
    static let OpenSettingsRequested = Notification.Name("OpenSettingsRequested")
    static let OpenDMsRequested = Notification.Name("OpenDMsRequested")
    
    // User stats
    static let UserPostCountDidChange = Notification.Name("UserPostCountDidChange")
    
    // Camera roll
    static let CameraRollImageSelected = Notification.Name("CameraRollImageSelected")
    static let CameraRollVideoSelected = Notification.Name("CameraRollVideoSelected")
    
    // Radius bar and capture
    static let currentPostRadiusDidChange = Notification.Name("CurrentPostRadiusDidChange")
    static let showCapturedPreviewRequested = Notification.Name("ShowCapturedPreviewRequested")
    static let capturePreviewDidDismiss = Notification.Name("CapturePreviewDidDismiss")
    static let radiusBarGlobeTap = Notification.Name("RadiusBarGlobeTap")
    static let radiusBarHoldBegan = Notification.Name("RadiusBarHoldBegan")
    static let radiusBarHoldEnded = Notification.Name("RadiusBarHoldEnded")
    static let animateRadiusBarToValue = Notification.Name("AnimateRadiusBarToValue")
}
