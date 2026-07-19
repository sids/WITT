# WITT Implementation Status

WITT is at the eighth integrated implementation milestone. The native SwiftUI app supports iPhone and iPad on iOS 26 and uses Core Data with private and shared CloudKit stores.

## Integrated Capabilities

- Browse, Search, Thing detail, known-QR add-Thing, and unknown-QR attach/create flows use immutable snapshots from `CoreDataCatalogRepository`.
- Browse opens directly on the selected Place's Rooms screen. A native Place menu switches or creates Places. The Place ellipsis menu contains Rename Place and Share Place, followed by a separated Print QR Labels action; a separate Shared management button appears when a CloudKit share exists.
- A Mail-style system toolbar provides the Place menu, full-catalog Thing search, and a full-screen QR scanner that closes back to the unchanged Browse position. Compact and regular layouts use the platform's native search placement without custom glass styling.
- Browse persists its selected Place and deepest destination across launches and reconstructs that screen's current active hierarchy after catalog loading. A moved destination restores through its new parent chain; missing, archived, and cyclic states fall back safely to an active Place root. Explicit Room taps replace any stale restored path before navigation.
- Browse gives each collection level a distinct presentation: two-column landscape Room tiles, image-led Storage Area rows, low-margin two-column Thing photo tiles, and low-margin two-column Container photo tiles. Room, Thing, and Container grids adapt to one column at accessibility Dynamic Type sizes. Room, Storage Area, and Container counts include every active descendant Thing, with malformed duplicate paths counted only once.
- Contextual creation controls continue through Rooms, Storage Areas, and Containers. New Room, Thing, and Container actions are tint-matched dashed tiles inside their grids. New Storage Area is a fully rounded standalone dashed row when the Room is empty; after Storage Areas exist, it becomes a transparent attached final row with a native separator above it and no dashed top edge. Its full-width circular stroke-border contour aligns both one-point tint sides with the native rows above and keeps the rounded bottom corners joined visibly to the dashed bottom edge inside the List mask. A 1.5-point same-path corner reinforcement optically matches the curves to the antialiased straight border. Creation sheets focus their primary name field immediately.
- Room screens keep Edit Room under a native ellipsis menu instead of exposing a standalone pencil toolbar button.
- New Storage Area and Container forms can scan and atomically bind any unused QR code with a non-empty payload. Existing target screens expose Attach/Reattach through ellipsis menus and a shared full-screen scanner; replacement releases the old label but never takes a healthy code attached elsewhere. The first-release invariant is one active QR per Storage Area or Container and one active target per payload.
- Storage Area details render as secondary text beneath the title. A native Things/Containers segmented control defaults to Things and switches the visible collection and contextual creation tile, while QR status stays out of Storage Area and Container content screens.
- AVFoundation QR scanning handles permission recovery, lifecycle, torch state, orientation, duplicate suppression, known destinations, unknown payloads, and damaged bindings. Denied access offers Open Settings, restricted and unavailable states use accurate copy, and foreground activation rechecks permission. Arbitrary non-empty QR payloads preserve exact identity, while valid generated WITT URLs unwrap to legacy raw tokens and external WITT deep links remain strictly validated.
- Camera capture uses the same denied/restricted/unavailable permission model, including Open Settings, Cancel, and foreground recovery. Camera and Photos picker input is normalized, stripped of metadata, resized, thumbnailed, and stored as explicit `PhotoAsset` records. Photo-library normalization is lifecycle-bound, prevents overlapping selection, cooperates with cancellation, and suppresses stale callbacks.
- Place-rooted CloudKit sharing includes private/shared stores, read/write participant sharing UI, and invitation acceptance.
- The production schema for `iCloud.in.sids.witt` was deployed and independently re-exported on July 15, 2026. It contains all eight Core Data-generated WITT record types and exact `ASSET` mappings for full and thumbnail `PhotoAsset` payloads. Debug-only, opt-in launch arguments validate or initialize future development schemas after both stores load; release builds contain no schema-initialization path.
- Unknown QR codes can be attached in one flow while selecting or creating a Room, Storage Area, and optional Container.
- Main scans and external WITT links open Repair QR directly for missing, archived, unsupported, duplicate, or conflicting bindings. The native repair flow preserves the payload and issue, shows eligible current and unassigned targets, offers Create & Attach, and atomically leaves one valid binding. Contextual Attach/Reattach can repair and explicitly replace the selected target's current QR after confirmation; general repair refuses healthy cross-target takeover.
- QR resolution is read-only. The optional deployed `QRCode.lastScannedAt` attribute remains inert for additive Core Data/CloudKit compatibility; runtime code neither reads nor writes it, and existing values remain untouched.
- Printable random QR labels use one physical-paper model for A4, US Letter, and Custom fixed or unlimited-length paper. Four paper margins, exact label dimensions, and horizontal/vertical gaps derive the grid. The default matches a 100 mm four-up roll of contiguous 25 × 25 mm square labels. Square labels are QR-only; rectangular labels put the ID beside the QR with an optional write-in line. Output retains validated geometry, Quick Look preview, share, and print.
- Place, Room, Storage Area, Container, and Thing support create, edit, same-Place move, photo replacement/removal, and cascading archive through explicit repository contracts and native management forms.
- Every managed-object class now has a WITT-prefixed Objective-C runtime name, while entity and Swift names remain unchanged. Repository insertion validates the model-to-type mapping before direct construction, preventing the device-only global `Container` class collision that crashed TestFlight build 4. Entity version hashes remain identical to build 4, and a real SQLite Container graph opens after recreation.
- A provider-isolated, Responses-compatible vision adapter supplies structured Thing labels and keywords in both Thing-creation paths. Manual fields and valid saves remain available while analysis is pending or unavailable; late suggestions preserve touched fields, and requests invalidated by save, dismissal, photo replacement, or removal cannot mutate stale forms.
- The planned production relay/auth contract, privacy controls, evaluation gates, and rollout safeguards are documented without compiling an unused relay client or synthetic evaluator into the app. Live AI still requires the operated relay/auth service, a consented photo corpus, provider/privacy decisions, and accepted gates.
- Both Thing-creation paths now continue to one shared native Thing Saved surface. Add Another Here starts a fresh Thing at the exact saved destination, while Scan Next, View Thing, and Done wait for the creation sheet to finish dismissing before reopening the scanner, navigating to the saved record, or returning to unchanged Browse. Successful saves return the exact new `ThingSnapshot`, so post-save routing never guesses identity.

## Production Boundaries

The production UI and AI transport boundary are integrated. Live AI still requires a WITT-owned relay or another secure short-lived credential strategy, a selected model, and an approved privacy policy. Long-lived provider credentials must never ship in the app bundle.

The next product-critical validation is real-device sharing between two iCloud accounts, particularly `PhotoAsset` binary transfer and bidirectional edits. Active work and TestFlight feedback belong only in [todo.md](todo.md); this page is not a backlog.

## Verification And Distribution

The July 19, 2026 baseline is 168 passing `wittTests` simulator tests in Debug and 164 in Release-optimized configuration. The four Debug-only tests cover the opt-in CloudKit schema launch-argument contract; the initializer and those tests are absent from Release. Remaining coverage includes persistence, managed-object runtime mappings and build-4 schema compatibility, containment and management mutations, selected-Place Browse restoration and descendant counts, deferred scanner and post-save handoffs, exact saved-Thing destination routing, arbitrary and generated QR identity compatibility, atomic QR creation/replacement/repair, duplicate-row consolidation, healthy-takeover refusal, inert legacy scan timestamps, QR repair routing and scanner decisions, scanner authorization transitions, camera permission mapping and recovery policy, QR printing, fixed/continuous physical label geometry and content rules, photo normalization and picker lifecycle, AI transport and configuration, manual-edit-preserving management-form helpers, adaptive presentation behavior, and Place sharing helpers. Both configurations completed with zero failures or skips; Debug and Release builds also completed cleanly. Release inspection confirms that screenshot demo routes, mock labeling, and speculative relay/evaluation symbols are absent.

Version 1.0 build 7 is `IN_BETA_TESTING` through the `WITT Internal` TestFlight group with auto-notify enabled. It adds arbitrary non-empty QR payload support and the latest Browse creation-control polish, including the final full-width New Storage Area treatment. Its source commit is `d723e9e`, and its App Store Connect build ID is `9d5cf61b-cd1a-40bb-b198-0c62cf2254c3`. On July 15, 2026, Sid confirmed that the affected iPhone successfully creates, saves, reopens, and retains a Container across relaunch, completing FB-024. See [release.md](release.md) for durable release facts and process.

## Project Documents

- [Documentation index](README.md)
- [Product brief](product.md)
- [Architecture](architecture.md)
- [AI labeling](ai-labeling.md)
- [AI production preparation](ai-production.md)
- [Product decision recommendations](product-decisions.md)
- [Todo tracker](todo.md)
- [Release](release.md)
- [App Store packaging](app-store.md)
- [App icon concepts](app-icon-concepts.md)
- [Place sharing spike](sharing-spike.md)
