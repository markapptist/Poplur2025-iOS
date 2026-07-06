# Street View setup (iOS: Apple MapKit Look Around)

The "Street View" button on the map screen uses Apple MapKit Look Around on iOS. It does not
use Mapbox or Mapillary — those are Android-only (see the `Poplur2025-Android` repo, which uses
Mapbox for the map and Mapillary for street-level imagery instead).

## Requirements

- No API key or access token is required for Look Around.
- Requires iOS 16+. The deployment target for this project is already 18.5, so this is satisfied
  automatically, but the code still checks availability at runtime and falls back to
  "Street View requires iOS 16 or later." if it's ever lowered below 16.

## Key files

- [LookAroundState.swift](Poplur2025/LookAroundState.swift) — button/flow state machine
  (`idle`, `noCoordinateSelected`, `checking`, `available`, `unavailable`, `unsupported`, `error`).
- [LookAroundService.swift](Poplur2025/LookAroundService.swift) — wraps `MKLookAroundSceneRequest`.
- [MapStreetViewViewModel.swift](Poplur2025/MapStreetViewViewModel.swift) — resolves the
  selected pin coordinate (falling back to the map camera center), cancels in-flight
  requests when a new one starts, and drives the state above.
- [StreetViewButton.swift](Poplur2025/StreetViewButton.swift) — the floating button on the map.
- [LookAroundContainerView.swift](Poplur2025/LookAroundContainerView.swift) — full-screen
  `MKLookAroundViewController` wrapper with a close button.

## Manual test steps

1. Open the Map tab.
2. Tap a location on the map (or leave nothing selected to use the current map center).
3. Tap "Street View" — it should show "Checking Street View…", then either open the Look
   Around viewer full-screen, or show "Street View is not available near this location."
4. Confirm the close (X) button in the viewer dismisses it back to the map.

## Known limitations

- Look Around coverage varies by location; many rural/international areas have no coverage.
- Requires a network connection; offline devices will surface the generic error state.
