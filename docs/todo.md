# WITT Todo

Updated July 12, 2026.

This is the canonical source of truth for actionable WITT work. New TestFlight feedback lands in the inbox before implementation starts.

Priority meanings:

- P0: release gate or blocks trustworthy testing.
- P1: next product or engineering work.
- P2: deliberately deferred; not committed scope until promoted.

Workflow:

1. Add each new observation with a stable ID, source/date, and affected build.
2. Preserve Sid's wording where useful, then add acceptance criteria during triage.
3. Move triaged work into the appropriate priority section; do not silently delete it.
4. Mark work complete only after verification, not merely implementation.
5. When a build ships, note it in [status.md](status.md) and [release.md](release.md), then remove completed tasks from this active list.
6. For every UI change, share simulator screenshots in the project-manager thread before calling the work complete. Cover each materially changed screen, include populated and empty states when relevant, and show both iPhone and iPad when responsive behavior differs.

## Feedback Inbox

- [ ] FB-001 - Continue collecting and triaging Sid's feedback on the current TestFlight build; latest is `1.0 (6)`. Close when Sid considers the review pass complete.
- [x] FB-018 - Sid, July 12, 2026, build `1.0 (4)`: Tighten the Room grid's horizontal margins so its tiles extend as far as the current New Room action. Make New Room a tile inside the two-column grid with a restrained dashed border. In the empty state, use the same dashed New Room tile but keep it centered rather than stretching it across the screen. Verified populated and empty states on iPhone; the adaptive two-column structure is unchanged on iPad.
- [x] FB-019 - Sid, July 12, 2026, build `1.0 (4)`: Fix Room navigation selecting a stale saved destination. Explicit Room taps now atomically replace a restored path, while launch restoration remains intact. Verified by three regression tests and by restoring a deep Garage path, backing to Home, selecting Home Office, and returning to Home.
- [x] FB-020 - Sid, July 12, 2026, build `1.0 (4)`: Make New Storage Area a full Storage Area list-sized action row with a restrained dashed border, in both empty and populated Room states. Verified on populated Garage and empty Home Office screens.
- [x] FB-021 - Sid, July 12, 2026, build `1.0 (4)`: Tighten the horizontal margins for Thing and Container grids. Put New Thing and New Container inside their corresponding two-column grids as square dashed-border tiles instead of a separate New menu, while preserving the same creation destinations. Verified on populated and empty Storage Area and Container states.
- [x] FB-022 - Sid, July 12, 2026, build `1.0 (4)`: Use the same system tint for dashed creation borders as the icon and text inside them, across New Room, Storage Area, Thing, and Container controls. Verified the shared tint treatment on New Storage Area, Thing, and Container controls; all use the same shared border component.
- [x] FB-023 - Sid, July 12, 2026, build `1.0 (4)`: Add a native Things/Containers segmented control to the Storage Area screen. The control defaults to Things and shows only the selected collection and matching contextual New tile. Verified populated Things and Containers plus an empty Storage Area on iPhone.
- [ ] FB-024 - Sid, July 12, 2026, build `1.0 (4)`, incident `BF869423-CB11-473C-AE71-11E3A434CF68`: Fix the release-device crash when adding a Container. The device-only abort was caused by Core Data resolving the unprefixed Objective-C runtime name `Container` to a foreign global class during generic entity insertion. All managed-object runtime names are now WITT-prefixed, insertion validates and directly constructs the expected type, build-4 entity hashes are pinned, and real SQLite Container recreation is covered in Debug and Release-optimized suites. Current replacement build `1.0 (6)` (`fdd162af-54ce-4cc4-967c-eb6296dc9966`) is `IN_BETA_TESTING`; close after Sid successfully creates and reopens a Container on the affected iPhone.
- [x] FB-025 - Sid, July 12, 2026, build `1.0 (5)`: Some rounded corners of the dashed New Room, Storage Area, Thing, and Container buttons were not visible. The shared creation border now draws its dashed sides and continuous rounded corners fully inside each control's bounds, preserving the current low-margin layouts and tint. Verified populated New Room and empty New Storage Area, Thing, and Container states on iPhone, plus the centered empty New Room state on iPad; all four corners remain visible at every tested aspect ratio.
- [x] FB-026 - Sid, July 12, 2026, build `1.0 (5)`: Move the Room screen's Edit action from a standalone toolbar button into an ellipsis menu. The Room toolbar now uses a native Room Actions menu with Edit Room and no standalone pencil button. Verified the menu presentation and edit-sheet transition on iPhone; the full 132-test simulator suite passes.
- [x] FB-027 - Sid, July 12, 2026, build `1.0 (5)`: Move Print QR Labels out of the persistent Place-switching menu and into the selected Place's native Place Actions ellipsis menu. Print QR Labels now appears after Rename Place and Share Place, separated by a divider, and is absent from the Place switcher. The existing print callback and presentation path are unchanged. Verified by a successful iOS 26 simulator build and the full 132-test simulator suite with zero failures.
- [x] FB-028 - Sid, July 12, 2026, build `1.0 (5)`: Replace the Code ID/Write-In print choices with physical label-paper configuration. A4 and US Letter now provide automatic dimensions; Custom accepts direct numeric width and Fixed or Unlimited length. Four paper margins, exact label width/height, and horizontal/vertical gaps derive the grid. Custom defaults to the linked True-Ally four-up roll: 100 mm unlimited paper, 25 × 25 mm labels, and zero margins/gaps. Square labels render QR-only; rectangular labels place the short ID beside the QR and optionally add a write-in line below it. Verified direct numeric entry on iPhone, a 100 × 300 mm four-up square PDF, a 100 × 600 mm two-up 50 × 25 mm write-in PDF, Poppler renders of both outputs, and all 134 simulator tests in Debug and Release-optimized configurations.
- [x] FB-029 - Sid, July 12, 2026, requested while build `1.0 (6)` was processing: Accept any non-empty QR-code payload for lookup and attachment instead of requiring a canonical `witt://` URL. Arbitrary payloads now preserve exact identity; valid generated WITT links unwrap to legacy raw-token rows; external WITT deep links remain strict; known/unknown routing, create-and-bind, replacement, and conflict protection all use the generalized identity. WITT-generated printable labels remain versioned `witt://` links, and attempting to construct one from an arbitrary payload returns a typed error rather than crashing. Verified by focused QR/repository/printing suites, then all 145 simulator tests in Debug and Release-optimized configurations with zero failures, skips, or warnings.
- [ ] FB-030 - Sid, July 12, 2026: Rename the App Store-facing app from `WITT: Where Is The Thing?` to match the new expansion, `WITT: Where Is That Thing?`. Apple rejected the exact requested name because it is already used by another account. Choose an available variant, update the `en-US` App Info localization, and verify the App Store Connect record while keeping the on-device icon label `WITT`.
- [x] FB-031 - Sid, July 12, 2026, build `1.0 (6)`: Repaired the dashed New Storage Area, New Thing, and New Container controls. The shared border now uses one continuous dashed system rounded rectangle, reinforces the four corner regions with the same native rounded geometry, and keeps grid content one point inside the List clipping boundary so no corner or adjoining edge disappears. New Storage Area retains a full Storage Area-row footprint, including its trailing media column, with deliberate vertical and horizontal separation from real rows. Verified populated Storage Area and Container states plus the empty Thing state in light and dark appearance on an iOS 26 iPhone, the empty state on an iOS 26 iPad, and all 145 tests in Debug and Release-optimized configurations with zero failures or skips; review screenshots were shared with Sid.

## P0 - Release Gates

- [ ] CLOUD-001 - Deploy or verify the production schema for `iCloud.in.sids.witt` before relying on synced or shared TestFlight data.
- [ ] CLOUD-002 - Run the real-device, two-iCloud-account Place-sharing spike.
  - [ ] Use two physical devices signed into different iCloud accounts.
  - [ ] Account A creates a Place graph containing Room, Storage Area, Container, Thing, keywords, QR binding, Place photo, thumbnail, and a realistic normalized Thing photo.
  - [ ] Account A shares the Place read/write; Account B accepts the invitation.
  - [ ] Verify the complete graph and every `PhotoAsset` render on Account B after cold launch.
  - [ ] Account B adds a photographed Thing; verify it and its photo on Account A.
  - [ ] Verify bidirectional name, keyword, movement, and photo edits.
  - [ ] Exercise invitation pending/acceptance, participant revocation, offline launch, reconnect, and recoverable error states.
  - [ ] Test fresh-install or additional-device hydration and measure first-share/photo latency.
  - [ ] Verify private/shared Place graph isolation and correct persistent-store assignment for new descendants.
  - [ ] Inspect CloudKit Dashboard/logs for record shape, assets, errors, and transfer size.
- [ ] CLOUD-003 - Decide the production photo design from the sharing-spike evidence.
  - [ ] Keep Core Data external Binary Data if transfer and performance are dependable.
  - [ ] If transfer is unreliable, design a hybrid `PhotoAsset` metadata + local files + shared CloudKit asset migration.
  - [ ] If reliable but slow, tune original/thumbnail dimensions and storage policy.
- [ ] AI-001 - Activate production AI without putting a long-lived provider key in the app.
  - [ ] Choose and implement a WITT-owned relay or secure short-lived credential strategy.
  - [ ] Choose the production model and Responses-compatible endpoint.
  - [ ] Decide and publish user-facing photo-processing, retention, and privacy disclosure.
  - [ ] Configure spend limits, rate limits, operational monitoring, and failure visibility.
  - [ ] Build a representative household-item photo evaluation set.
  - [ ] Evaluate naming, keywords, details, refusal, irrelevant text, latency, offline behavior, and manual fallback.
  - [ ] Enable the remote service in a release build only after the evaluation passes.
- [ ] QA-001 - Complete physical-device cataloging and accessibility QA on iPhone and iPad.
  - [ ] Exercise first launch, Browse, Search, known QR, unknown QR, add/edit/move/archive, photo replacement, print/share, deep links, and Place sharing.
  - [ ] Print labels and catalogue at least 10 real Things in one moving-around-the-home session; record taps, typing, delay, and navigation friction.
  - [ ] Verify camera/Photos permissions, denied/restricted recovery, torch, background/foreground transitions, interruption, offline launch, and sync-pending states.
  - [ ] Verify Dynamic Type, VoiceOver labels/order, contrast, hit targets, iPad keyboard navigation, rotation, and split-view sizing.
  - [ ] Repeat camera/photo ingestion long enough to expose memory growth or thermal issues.

## P1 - Product And UX

- [ ] UX-001 - Design and implement the fast post-save loop. Decide the default among Scan Next and Add Another Here while keeping View Thing available; the current flow returns to Browse.
- [ ] UX-002 - Let users enter and save Thing details manually while AI analysis is slow or unavailable instead of disabling the form until analysis completes.
- [ ] UX-003 - Add actionable camera-denied recovery, including Open Settings; decide whether manual QR entry belongs in the first release.
- [ ] QR-001 - Decide whether a Storage Area or Container can have multiple QR codes. Align data rules, eligible-target queries, binding UI, conflict behavior, and docs.
- [ ] QR-002 - Turn `needsRepair` and QR conflict alerts into a complete repair flow for archived, missing, or multiply bound targets.
- [ ] SEARCH-001 - Decide the scope and prominence of duplicate-Thing detection; implement only if it materially helps cataloging.
- [ ] AI-002 - Decide whether AI confidence is user-visible or only used internally to flag suggestions for review.
- [ ] THING-001 - Decide whether quantity belongs in first-release Thing capture.
- [ ] PLACE-001 - Decide whether direct-to-Room Thing placement is a normal path or a fallback when no Storage Area/Container applies.
- [ ] SHARE-001 - After real shared-Place use, confirm whether simple last-writer conflict behavior is acceptable or needs user-facing conflict handling.

## P1 - Engineering And Operations

- [ ] CLOUD-004 - Add restrained CloudKit sync diagnostics after the sharing spike identifies useful failure signals.
- [ ] PHOTO-001 - Profile camera and photo-library ingestion during long physical sessions; optimize normalization, thumbnails, and memory use if evidence requires it.
- [ ] QR-003 - Decide whether `QRCode.lastScannedAt` should become maintained product metadata or be removed.
- [ ] TEST-001 - Add focused regression tests with each feedback fix and keep the full simulator suite green.

## P2 - App Store Release

- [ ] RELEASE-001 - Replace the provisional app icon with an approved production icon.
- [ ] RELEASE-002 - Prepare App Store metadata, screenshots, privacy/support URLs, App Privacy answers, age rating, category, description, keywords, and review notes.
- [ ] RELEASE-003 - Archive with an Apple-accepted stable Xcode before App Store submission if the beta toolchain is no longer accepted.
- [ ] RELEASE-004 - Complete final release-device, CloudKit, AI, privacy, accessibility, and data-loss checks before submitting version 1.0.

## P2 - Parking Lot

Do not schedule these until Sid explicitly promotes them:

- [ ] LATER-001 - Multi-photo capture for a Thing.
- [ ] LATER-002 - Thing location history or move events.
- [ ] LATER-003 - Persisted printable-QR batches, provenance, and reprint history.
- [ ] LATER-004 - Durable provider-neutral AI attempt history or an explicit audit/debug mode.
- [ ] LATER-005 - Advanced shared-edit conflict UI beyond simple last-writer behavior.
- [ ] LATER-006 - Richer Container/Storage Area metadata such as kind, capacity, wall, shelf, or label hints.

Build `1.0 (2)` resolved feedback FB-002 through FB-008. See [status.md](status.md) and [release.md](release.md) for the shipped state.

Build `1.0 (3)` resolved feedback FB-009 through FB-014 and completed TF-002. It passed 108 simulator tests and is in internal beta testing; see [status.md](status.md) and [release.md](release.md).

Build `1.0 (6)` contains FB-025 through FB-028, passed 134 simulator tests in Debug and Release-optimized configurations, and is in internal beta testing. The arbitrary-QR work in FB-029 was completed afterward and is not part of build 6; see [status.md](status.md) and [release.md](release.md).
