/*
 AR Filter Camera Freeze Fix
 ============================
 
 ISSUES FIXED:
 
 1. Camera Freezing When AR Filter Menu Opens
    CAUSE: Display layer wasn't visible/receiving frames
    FIX: Switch between preview layer and display layer based on filter state
    
    - Normal operation: AVCaptureVideoPreviewLayer (visible)
    - AR filter active: AVSampleBufferDisplayLayer (visible)
    - This ensures continuous video feed in both modes
 
 2. Double-Tap Camera Flip Not Working
    CAUSE: All gestures were being disabled when AR filters shown
    FIX: Only disable navigation gestures, keep camera controls always active
    
    ALWAYS ENABLED:
    - Double-tap (flip camera)
    - Swipe up/down (torch toggle)
    
    CONDITIONALLY DISABLED (when AR filters shown):
    - Pan (navigation between tabs)
 
 IMPLEMENTATION:
 
 handleARFiltersStateChanged():
 - When AR filters shown:
   * Hide preview layer
   * Show display layer
   * Disable navigation only
 - When AR filters hidden:
   * Show preview layer  
   * Hide display layer
   * Re-enable navigation
 
 handleARFilterChanged():
 - When filter active (!= .none):
   * Use display layer for processing
 - When no filter (.none):
   * Use preview layer for performance
 
 setGesturesEnabled():
 - NEVER disables double-tap or swipe gestures
 - Only controls pan gesture (navigation)
 
 RESULT:
 ✅ Camera feed never freezes
 ✅ Double-tap always works
 ✅ Torch controls always work
 ✅ Smooth layer transitions
 */
