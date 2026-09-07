# Shared layout browser trial

This branch contains the verified web bundle from `poplur-clay-map` commit
`5ad3efb2635ab3214ba13f4405cde58270b1a3a3`. Native SwiftUI application code is
unchanged. The separate native-screen experiment is parked on
`trial/native-shell-2026-09-07`.

The user chose shared layouts across platforms, native media capabilities and
WebGL only for Map as the migration target. This first slice removes live WebGL
from bundled navigators and the Feed/Profile/News controls. Custom unbaked GLBs
and specialized 3D games/avatar tools still retain their existing renderers.
Existing camera integration and platform media decoding remain in use.

The guarded production sync passed without changing thermal budgets. All 1,379
bundled files match the same frozen build in native Android. The production
Profile/Feed probes recorded zero WebGL contexts. These desktop checks do not
prove that the physical iPhone overheating is resolved.

**Device installation is held for browser review and subsequent user
authorization. This checkpoint does not authorize installing on iPhone, iPad
or Watch.** No trial build has been installed. Expo is excluded entirely.

Rollback baseline: `checkpoint/pre-native-shell-2026-09-07`.
The local evidence is in the workspace's
`.codex/install-reports/shared-ui-preview-20260907/` directory.
