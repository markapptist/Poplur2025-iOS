# Shared layout device trial — Feed controls follow-up

This branch contains the verified web bundle from `poplur-clay-map` commit
`04bdc8204d328a2462e3f97a75e50229cd517715`. Native Swift application code is
unchanged. The user chose shared layouts, native media capabilities and WebGL
only for Map as the migration target, then approved trials on iPhone and Android.
Expo builds and installations remain excluded.

Manual Feed D-pad and dial choices now stay selected, including empty channels
and across feed/location updates. The sprite navigator responds to tilt without
a prior touch and beyond three seconds. It renews the native motion lease while
visible, stops on background/hidden edges, and switches images only on meaningful
pose changes. No navigator WebGL context or animation clock was restored.

The production thermal gate passed without a skip or budget increase. All 1,439
web files exactly match the frozen build in native Android. Home, Feed and Profile
have zero WebGL contexts; Map has one. Map retained heap remained 17.2 MB across
the measured 60-second dwell with zero idle renders. There are 58 passing focused
web tests, including manual empty-channel tuning and sensor lifecycle coverage.

The first iPhone trial was installed, but its heat recording was stopped after
the controls failed. Its logs reached a fair thermal state. These desktop checks
do not prove physical-device overheating is resolved; the corrected build needs
a separate active-use endurance result. Package and device verification receipts
are recorded in `.codex/install-reports/shared-ui-profile-20260907/` in the parent
workspace. iPad, Watch, tablet and Wear installations are outside this request.

Custom unbaked GLBs and specialized 3D games/avatar tools retain their renderers.
Existing camera integration and platform media decoding remain in use.
Rollback baseline: `checkpoint/pre-native-shell-2026-09-07`.

## Profile cached-thumbnail correction

The user confirmed both Feed controls and tilt on iPhone. Entering Profile then
failed with React error 185 at the cached poster callback ref. Profile posters
now own readiness and static-overlay state locally, with stable image refs.
A thumbnail no longer schedules Profile-wide state from the commit phase.
This keeps the existing appearance while removing that feedback path.

37 additional targeted tests pass, as do TypeScript and governed loops. A
production native-bridge fixture with six cached posters and repeated post
refreshes remains visible with zero runtime errors and zero canvases. That
Chrome fixture also passes on the old build; the failure evidence is the
iPhone diagnostic stack, and physical-device confirmation is still required.
The guarded thermal gate passes with no budget changes or skips.

## Feed content stability correction

Shared web source `cffde7d93cee5a5fb349c509acc94c0ca1dab885` keeps tester mode
under the server configuration instead of allowing the private event endpoint's
disabled response to clear it. Native Feed subscriptions also retain the already
delivered posts when another screen subscribes or an explicit refresh starts.

The two behavioral regressions are covered by three tests that fail before the
fix and pass after. All 43 focused tests and TypeScript pass. The shared DOM/CSS
layout and renderer policy are unchanged. Profile has been confirmed working
on the previous installed correction by the iPhone user and Android screenshot.

Build/install evidence: parent workspace
`.codex/install-reports/feed-channel-loading-20260907/`. The latest two-minute
recording was stopped because Feed content was unreliable; it does not count as
an endurance pass. The user subsequently reported much less warmth from the
rendering changes already installed on iPhone; objective sustained-use thermal
verification remains separate.

## Plain Camera processing follow-up

The user reported warmth during plain live preview. A retained video-data output
could be reopened by a policy update after Scan was disabled, and installing a
Lens output also left generic processing demand enabled. Every output reopening
now requires current Scan or Lens demand and an active capture lease. Turning
Scan off releases its demand even while a Lens owns the output; dismissing that
Lens then closes the data branch. The separate native preview remains at its
existing resolution and rate.

`scripts/test-camera-frame-demand.py` executes the controller's actual delivery
methods with connection/delegate doubles. Five lifecycle assertions fail before
the correction and all scenarios pass afterward. Nine web camera controls and
availability tests pass. This proves the processing lifecycle defect, not that
it caused all reported warmth. The one-minute device sample happened on Map
after the user left Camera, so it is not a Camera endurance result. New capture
and frame-delivery transition logs support the next physical test.
