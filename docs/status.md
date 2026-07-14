# WITT Implementation Status

WITT is at the seventh integrated implementation milestone. The native SwiftUI app supports iPhone and iPad on iOS 26 and uses Core Data with private and shared CloudKit stores.

## Integrated Capabilities

- Browse, Search, Thing detail, known-QR add-Thing, and unknown-QR attach/create flows use immutable snapshots from `CoreDataCatalogRepository`.
- Browse opens directly on the selected Place's Rooms screen. A native Place menu switches or creates Places. The Place ellipsis menu contains Rename Place and Share Place, followed by a separated Print QR Labels action; a separate Shared management button appears when a CloudKit share exists.
- A Mail-style system toolbar provides the Place menu, full-catalog Thing search, and a full-screen QR scanner that closes back to the unchanged Browse position. Compact and regular layouts use the platform's native search placement without custom glass styling.
- Browse persists its selected Place and deepest destination across launches and reconstructs that screen's current active hierarchy after catalog loading. A moved destination restores through its new parent chain; missing, archived, and cyclic states fall back safely to an active Place root. Explicit Room taps replace any stale restored path before navigation.
- Browse gives each collection level a distinct presentation: two-column landscape Room tiles, image-led Storage Area rows, low-margin two-column Thing photo tiles, and low-margin two-column Container photo tiles. Room, Storage Area, and Container counts include every active descendant Thing, with malformed duplicate paths counted only once.
- Contextual creation controls continue through Rooms, Storage Areas, and Containers. New Room, Thing, and Container actions are tint-matched dashed tiles inside their grids. New Storage Area is a fully rounded standalone dashed row when the Room is empty; after Storage Areas exist, it becomes a transparent attached final row with a native separator above it and no dashed top edge. Its full-width circular stroke-border contour aligns both one-point tint sides with the native rows above and keeps the rounded bottom corners joined visibly to the dashed bottom edge inside the List mask. A 1.5-point same-path corner reinforcement optically matches the curves to the antialiased straight border. Creation sheets focus their primary name field immediately.
- Room screens keep Edit Room under a native ellipsis menu instead of exposing a standalone pencil toolbar button.
- New Storage Area and Container forms can scan and atomically bind any unused QR code with a non-empty payload. Existing target screens expose Attach/Reattach through ellipsis menus and a shared full-screen scanner; replacement releases the old label but never takes a code attached elsewhere.
- Storage Area details render as secondary text beneath the title. A native Things/Containers segmented control defaults to Things and switches the visible collection and contextual creation tile, while QR status stays out of Storage Area and Container content screens.
- AVFoundation QR scanning handles permissions, lifecycle, torch state, orientation, duplicate suppression, known destinations, and unknown payloads. Arbitrary non-empty QR payloads preserve exact identity, while valid generated WITT URLs unwrap to legacy raw tokens and external WITT deep links remain strictly validated.
- Camera and Photos picker input is normalized, stripped of metadata, resized, thumbnailed, and stored as explicit `PhotoAsset` records.
- Place-rooted CloudKit sharing includes private/shared stores, read/write participant sharing UI, and invitation acceptance.
- Unknown QR codes can be attached in one flow while selecting or creating a Room, Storage Area, and optional Container.
- Printable random QR labels use one physical-paper model for A4, US Letter, and Custom fixed or unlimited-length paper. Four paper margins, exact label dimensions, and horizontal/vertical gaps derive the grid. The default matches a 100 mm four-up roll of contiguous 25 × 25 mm square labels. Square labels are QR-only; rectangular labels put the ID beside the QR with an optional write-in line. Output retains validated geometry, Quick Look preview, share, and print.
- Place, Room, Storage Area, Container, and Thing support create, edit, same-Place move, photo replacement/removal, and cascading archive through explicit repository contracts and native management forms.
- Every managed-object class now has a WITT-prefixed Objective-C runtime name, while entity and Swift names remain unchanged. Repository insertion validates the model-to-type mapping before direct construction, preventing the device-only global `Container` class collision that crashed TestFlight build 4. Entity version hashes remain identical to build 4, and a real SQLite Container graph opens after recreation.
- A provider-isolated, Responses-compatible vision adapter supplies structured Thing labels and keywords in both Thing-creation paths.

## Production Boundaries

The production UI and AI transport boundary are integrated. Live AI still requires a WITT-owned relay or another secure short-lived credential strategy, a selected model, and an approved privacy policy. Long-lived provider credentials must never ship in the app bundle.

The next product-critical validation is real-device sharing between two iCloud accounts, particularly `PhotoAsset` binary transfer and bidirectional edits. Active work and TestFlight feedback belong only in [todo.md](todo.md); this page is not a backlog.

## Verification And Distribution

The baseline is 145 passing `wittTests` simulator tests in both Debug and Release-optimized configurations. Coverage includes persistence, managed-object runtime mappings and build-4 schema compatibility, containment and management mutations, selected-Place Browse restoration, explicit Room-path replacement and descendant counts, deferred scanner routing, arbitrary and generated QR identity compatibility, atomic QR creation/replacement, QR routing, scanning and printing, fixed/continuous physical label geometry and content rules, photo normalization, AI transport, management-form helpers, presentation behavior, and Place sharing helpers.

Version 1.0 build 7 is `IN_BETA_TESTING` through the `WITT Internal` TestFlight group with auto-notify enabled. It adds arbitrary non-empty QR payload support and the latest Browse creation-control polish, including the final full-width New Storage Area treatment. Its source commit is `d723e9e`, and its App Store Connect build ID is `9d5cf61b-cd1a-40bb-b198-0c62cf2254c3`. The affected iPhone still needs to confirm manual Container creation before FB-024 closes. See [release.md](release.md) for durable release facts and process.

## Project Documents

- [Documentation index](README.md)
- [Product brief](product.md)
- [Architecture](architecture.md)
- [AI labeling](ai-labeling.md)
- [Todo tracker](todo.md)
- [Release](release.md)
