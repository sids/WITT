# WITT Todo

Updated July 15, 2026.

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

- [ ] FB-001 - Continue collecting and triaging Sid's feedback on the current TestFlight build; latest is `1.0 (7)`. Close when Sid considers the review pass complete.
- [ ] TF-003 - Add Divya to `WITT Internal` for the two-account sharing spike. Sid grants her WITT app visibility in App Store Connect while retaining her current apps and SALES role; Codex then sends and verifies the TestFlight group invitation.
- [x] FB-018 - Sid, July 12, 2026, build `1.0 (4)`: Tighten the Room grid's horizontal margins so its tiles extend as far as the current New Room action. Make New Room a tile inside the two-column grid with a restrained dashed border. In the empty state, use the same dashed New Room tile but keep it centered rather than stretching it across the screen. Verified populated and empty states on iPhone; the adaptive two-column structure is unchanged on iPad.
- [x] FB-019 - Sid, July 12, 2026, build `1.0 (4)`: Fix Room navigation selecting a stale saved destination. Explicit Room taps now atomically replace a restored path, while launch restoration remains intact. Verified by three regression tests and by restoring a deep Garage path, backing to Home, selecting Home Office, and returning to Home.
- [x] FB-020 - Sid, July 12, 2026, build `1.0 (4)`: Make New Storage Area a full Storage Area list-sized action row with a restrained dashed border, in both empty and populated Room states. Verified on populated Garage and empty Home Office screens.
- [x] FB-021 - Sid, July 12, 2026, build `1.0 (4)`: Tighten the horizontal margins for Thing and Container grids. Put New Thing and New Container inside their corresponding two-column grids as square dashed-border tiles instead of a separate New menu, while preserving the same creation destinations. Verified on populated and empty Storage Area and Container states.
- [x] FB-022 - Sid, July 12, 2026, build `1.0 (4)`: Use the same system tint for dashed creation borders as the icon and text inside them, across New Room, Storage Area, Thing, and Container controls. Verified the shared tint treatment on New Storage Area, Thing, and Container controls; all use the same shared border component.
- [x] FB-023 - Sid, July 12, 2026, build `1.0 (4)`: Add a native Things/Containers segmented control to the Storage Area screen. The control defaults to Things and shows only the selected collection and matching contextual New tile. Verified populated Things and Containers plus an empty Storage Area on iPhone.
- [x] FB-024 - Sid, July 12, 2026, build `1.0 (4)`, incident `BF869423-CB11-473C-AE71-11E3A434CF68`: Fix the release-device crash when adding a Container. The device-only abort was caused by Core Data resolving the unprefixed Objective-C runtime name `Container` to a foreign global class during generic entity insertion. All managed-object runtime names are now WITT-prefixed, insertion validates and directly constructs the expected type, build-4 entity hashes are pinned, and real SQLite Container recreation is covered in Debug and Release-optimized suites. Verified July 15, 2026 in replacement build `1.0 (7)` (`9d5cf61b-cd1a-40bb-b198-0c62cf2254c3`): Sid successfully created and saved a Container on the affected iPhone, reopened it, and confirmed it survived relaunch.
- [x] FB-025 - Sid, July 12, 2026, build `1.0 (5)`: Some rounded corners of the dashed New Room, Storage Area, Thing, and Container buttons were not visible. The shared creation border now draws its dashed sides and continuous rounded corners fully inside each control's bounds, preserving the current low-margin layouts and tint. Verified populated New Room and empty New Storage Area, Thing, and Container states on iPhone, plus the centered empty New Room state on iPad; all four corners remain visible at every tested aspect ratio.
- [x] FB-026 - Sid, July 12, 2026, build `1.0 (5)`: Move the Room screen's Edit action from a standalone toolbar button into an ellipsis menu. The Room toolbar now uses a native Room Actions menu with Edit Room and no standalone pencil button. Verified the menu presentation and edit-sheet transition on iPhone; the full 132-test simulator suite passes.
- [x] FB-027 - Sid, July 12, 2026, build `1.0 (5)`: Move Print QR Labels out of the persistent Place-switching menu and into the selected Place's native Place Actions ellipsis menu. Print QR Labels now appears after Rename Place and Share Place, separated by a divider, and is absent from the Place switcher. The existing print callback and presentation path are unchanged. Verified by a successful iOS 26 simulator build and the full 132-test simulator suite with zero failures.
- [x] FB-028 - Sid, July 12, 2026, build `1.0 (5)`: Replace the Code ID/Write-In print choices with physical label-paper configuration. A4 and US Letter now provide automatic dimensions; Custom accepts direct numeric width and Fixed or Unlimited length. Four paper margins, exact label width/height, and horizontal/vertical gaps derive the grid. Custom defaults to the linked True-Ally four-up roll: 100 mm unlimited paper, 25 × 25 mm labels, and zero margins/gaps. Square labels render QR-only; rectangular labels place the short ID beside the QR and optionally add a write-in line below it. Verified direct numeric entry on iPhone, a 100 × 300 mm four-up square PDF, a 100 × 600 mm two-up 50 × 25 mm write-in PDF, Poppler renders of both outputs, and all 134 simulator tests in Debug and Release-optimized configurations.
- [x] FB-029 - Sid, July 12, 2026, requested while build `1.0 (6)` was processing: Accept any non-empty QR-code payload for lookup and attachment instead of requiring a canonical `witt://` URL. Arbitrary payloads now preserve exact identity; valid generated WITT links unwrap to legacy raw-token rows; external WITT deep links remain strict; known/unknown routing, create-and-bind, replacement, and conflict protection all use the generalized identity. WITT-generated printable labels remain versioned `witt://` links, and attempting to construct one from an arbitrary payload returns a typed error rather than crashing. Verified by focused QR/repository/printing suites, then all 145 simulator tests in Debug and Release-optimized configurations with zero failures, skips, or warnings.
- [ ] FB-030 - Sid, July 12, 2026: Rename the App Store-facing app from `WITT: Where Is The Thing?` to match the new expansion, `WITT: Where Is That Thing?`. Apple rejected the exact requested name because it is already used by another account. Choose an available variant, update the `en-US` App Info localization, and verify the App Store Connect record while keeping the on-device icon label `WITT`.
- [x] FB-031 - Sid, July 12, 2026, build `1.0 (6)`: Repaired the dashed New Storage Area, New Thing, and New Container controls. The shared border now uses one continuous dashed system rounded rectangle, reinforces the four corner regions with the same native rounded geometry, and keeps grid content one point inside the List clipping boundary so no corner or adjoining edge disappears. New Storage Area retains a full Storage Area-row footprint, including its trailing media column, with deliberate vertical and horizontal separation from real rows. Verified populated Storage Area and Container states plus the empty Thing state in light and dark appearance on an iOS 26 iPhone, the empty state on an iOS 26 iPad, and all 145 tests in Debug and Release-optimized configurations with zero failures or skips; review screenshots were shared with Sid.
- [x] FB-032 - Sid, July 13, 2026, build `1.0 (6)`: New Storage Area now has two distinct treatments. An empty Room retains the standalone button with a fully dashed rounded outline. In a populated Room, the action is the attached final list row with no gap or top border, dashed side and bottom borders, and only the bottom corners rounded. Verified both states in light and dark appearance on an iOS 26 iPhone, removed the temporary empty-Room fixture afterward, and passed all 145 tests in Debug and Release-optimized configurations with zero failures or skips; review screenshots were shared with Sid.
- [x] FB-033 - Sid, July 14, 2026, build `1.0 (6)`: Finished correcting the populated New Storage Area row after rejecting the filled-row attempt in `25a4b24`, the misaligned inset corners in `a866057`, and the narrowed contour in `dea7521`. Commit `c4c0cd7` established the accepted full-width geometry: transparent attached row, native-looking separator, no dashed top edge, aligned one-point sides, and visible tangent 24-point circular bottom corners. The remaining optical defect was fixed by increasing only the same-path corner reinforcement to 1.5 points, compensating for native-mask antialiasing without changing coordinates, tint, radius, or tangent joins. Matched 9 x 9 neighborhood measurements confirm comparable peak and average luminance across side dashes, bottom dashes, and both arcs in light and dark; the empty-state treatment remains unchanged. Verified 368 x 800 light and dark iOS 26 iPhone screenshots, then passed all 145 tests in Debug and Release-optimized configurations with zero failures or skips.

## P0 - Release Gates

- [x] CLOUD-001 - Production schema for `iCloud.in.sids.witt` was initialized from the build-7 Core Data model, reviewed, deployed, and independently re-exported on July 15, 2026. Production matches development exactly: eight WITT `CD_*` record types, generated indexes and security roles, and both `PhotoAsset` payloads mapped to companion `ASSET` fields.
- [ ] CLOUD-002 - Run the real-device, two-iCloud-account Place-sharing spike.
  - Execution runbook and evidence record: [sharing-spike.md](sharing-spike.md).
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

- [x] UX-001 - Implement the fast post-save loop with Add Another Here as the primary action. Completed July 15, 2026.
  - [x] After either known-QR Review Thing or contextual Add Thing saves successfully, show one concise native Thing Saved surface instead of returning immediately to Browse.
  - [x] Add Another Here starts a fresh Thing at the same exact destination; Scan Next dismisses before opening the full-screen scanner.
  - [x] View Thing dismisses and navigates Browse to the exact saved Thing; Done returns to the unchanged Browse position.
  - [x] Verified 4 focused state/routing tests, all 155 Debug tests, all 151 Release-optimized tests, a clean simulator build, and an iOS 26 simulator render of the shared post-save surface used by both entry paths.
- [x] UX-002 - Let users enter and save Thing details manually while AI analysis is slow or unavailable instead of disabling the form until analysis completes. Completed July 15, 2026.
  - [x] Keep fields editable and enable Save from normal form validity alone in both known-QR Review Thing and contextual Add Thing flows.
  - [x] Apply late AI suggestions only to fields the user has not already filled or changed; never overwrite manual input.
  - [x] Ignore stale AI results after save, dismissal, photo replacement, or photo removal, while preserving honest failure and retry states.
  - [x] Verified 11 focused state tests, all 151 Debug tests, all 147 Release-optimized tests, and iOS 26 simulator screenshots covering active analysis and unavailable manual-entry states in both creation paths.
- [x] UX-003 - Add actionable camera-denied recovery; manual QR entry is deferred from the first release. Completed July 15, 2026.
  - [x] When camera permission is denied, QR scanning and photo capture show accurate native recovery copy with an Open Settings action and a clear way back.
  - [x] Restricted and unavailable camera states explain the limitation without implying that permission can always be changed.
  - [x] Returning from Settings refreshes authorization and resumes the requested camera flow when access has been granted.
  - [x] Verified 20 focused permission/photo/scanner tests, all 160 Debug tests, all 156 Release-optimized tests, clean simulator builds, and iOS 26 simulator renders of both denied-camera surfaces.
- [x] QR-001 - Enforce the first-release rule of exactly one active QR per Storage Area or Container and one active target per QR payload; multiple labels per target are deferred.
  - [x] Product decision locked July 15, 2026.
  - [x] Ordinary attach/reattach, eligible-target queries, conflict behavior, and user-facing copy follow the rule.
  - [x] Repository coverage proves healthy cross-target takeover is refused and replacement/repair leaves one valid binding.
- [x] QR-002 - Replace `needsRepair` and QR conflict dead ends with a complete repair flow for archived, missing, unsupported, or multiply bound targets.
  - [x] Main scans and external WITT links open Repair QR directly with the payload and issue preserved.
  - [x] Show conflicting active destinations and eligible unassigned Storage Areas/Containers immediately, with Create & Attach available.
  - [x] Existing-target, new-target-draft, and create-and-attach repair paths are explicit and never take a healthy binding implicitly.
  - [x] Existing-target and create-and-attach repairs atomically consolidate all damaged/duplicate rows into exactly one chosen binding.
  - [x] Verified July 15, 2026 with 171 Debug tests, 167 Release-optimized tests, clean iOS 26 Debug build/run, and conflict/list plus no-target/create repair screenshots.
- [ ] SEARCH-001 - Decide the scope and prominence of duplicate-Thing detection; implement only if it materially helps cataloging.
- [ ] AI-002 - Decide whether AI confidence is user-visible or only used internally to flag suggestions for review.
- [ ] THING-001 - Decide whether quantity belongs in first-release Thing capture.
- [ ] PLACE-001 - Decide whether direct-to-Room Thing placement is a normal path or a fallback when no Storage Area/Container applies.
- [ ] SHARE-001 - After real shared-Place use, confirm whether simple last-writer conflict behavior is acceptable or needs user-facing conflict handling.

## P1 - Engineering And Operations

- [ ] CLOUD-004 - Add restrained CloudKit sync diagnostics after the sharing spike identifies useful failure signals.
- [ ] PHOTO-001 - Profile camera and photo-library ingestion during long physical sessions; optimize normalization, thumbnails, and memory use if evidence requires it.
- [x] QR-003 - Retire `QRCode.lastScannedAt` from runtime behavior while retaining the optional deployed model attribute for additive CloudKit compatibility. QR resolution stays read-only and preserves legacy values without creating scan-history writes. Verified July 15, 2026 with 47 focused repository and persistence tests.
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

Build `1.0 (7)` contains FB-029 and the final Browse creation-control polish from FB-031 through FB-033. It passed all 145 simulator tests in Debug and clean Release-optimized configurations and is `IN_BETA_TESTING` in `WITT Internal`; see [status.md](status.md) and [release.md](release.md).
