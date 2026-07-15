# WITT Architecture

This document describes the architecture implemented in the WITT iOS app. Product intent remains in [product.md](product.md); this document records the current technical shape and the boundaries that still require production validation.

WITT is a native SwiftUI app for iPhone and iPad with a minimum deployment target of iOS 26. Core Data is the system of record, `NSPersistentCloudKitContainer` provides private and shared iCloud stores, and a `Place` is both the top-level domain boundary and the unit of sharing.

## Dependency assembly and app shell

[`WITTApp`](../witt/ContentView.swift) owns the process-wide `PersistenceController.shared`, injects its `viewContext`, and creates `ContentView`. `ContentView` is the composition root for app-facing dependencies:

- It creates the main-actor `CatalogStore` around the persistence controller.
- It selects a `ThingPhotoLabelingService` through `ThingPhotoLabelingServices.appDefault()` and injects it through SwiftUI environment values.
- It passes the repository to `AppShellView` through the narrower `QRCodeResolving` contract for deep-link resolution.
- It bootstraps the catalog and reloads immutable presentation snapshots when Core Data posts a remote-store change.

[`AppShellView`](../witt/App/AppShellView.swift) is the application coordinator. It hosts one persistent Browse surface and owns transient routing state for the full-screen scanner, Place sharing, QR PDF printing, deep-link alerts, and debug-only demo entry points. Scanner payloads are staged until the camera dismisses, then passed through the same deep-link router used for external URLs. Known QR destinations open the photo-first add-Thing flow; unknown tokens open attachment directly; damaged or conflicting bindings produce repair-oriented alerts rather than guessing.

CloudKit invitation entry is bridged from UIKit scene callbacks by `WITTAppDelegate`, `WITTSceneDelegate`, and `PlaceShareAcceptanceCenter` in [`CloudKitShareDelegates.swift`](../witt/Sharing/CloudKitShareDelegates.swift). Successful acceptance reloads the catalog.

## Domain model and containment invariants

The domain stays explicit rather than using a generic inventory tree:

- `Place` is the ownership, persistence-store, and sharing root.
- `Room` belongs to exactly one Place.
- `Area` is the model name for a Storage Area. It belongs to exactly one Room and the same Place as that Room.
- `Container` belongs to one Place and has exactly one parent: a Room, Area, or another Container. Nested Containers are supported.
- `Thing` belongs to one Place and has exactly one current home: a Room, Area, or Container.
- `ThingKeyword` belongs to one Thing and the same Place.
- `QRCode` can bind only to an Area or Container. A bound code has exactly one target in the same Place; an unbound code has no target.
- `PhotoAsset` belongs to one Place and exactly one supported owner: Place, Area, Container, or Thing. Rooms intentionally do not have photos in the current model.

The same-Place rule applies to moves as well as creation. A Container cannot be moved into itself or any descendant. Archive operations are soft deletes using `archivedAt` and cascade through the active containment subtree; Place archive covers its Rooms, Areas, Containers, and Things. QR and photo records remain in the Place graph, allowing damaged bindings to resolve as `needsRepair` instead of silently reusing an identity.

These rules are represented without managed objects in [`ContainmentValidation.swift`](../witt/Domain/ContainmentValidation.swift), enforced against Core Data relationships by [`ManagedObjectValidation.swift`](../witt/Domain/ManagedObjectValidation.swift), and checked before repository saves. Snapshot construction also rejects stored rows with ambiguous parents or missing identity. [`CatalogPresentation.swift`](../witt/App/CatalogPresentation.swift) filters archived or structurally inactive descendants and derives safe location paths, move choices, and archive impact from the immutable graph.

## Core Data and repository boundaries

The Core Data schema in [`WITT.xcdatamodel`](../witt/WITT.xcdatamodeld/WITT.xcdatamodel/contents) contains `Place`, `Room`, `Area`, `Container`, `Thing`, `ThingKeyword`, `QRCode`, and `PhotoAsset`. Every entity is CloudKit-syncable. Place has cascade relationships to the complete Place-owned graph; redundant direct `place` relationships on descendants make ownership and store placement explicit even when containment is nested.

[`ManagedObjects.swift`](../witt/Persistence/ManagedObjects.swift) contains the `NSManagedObject` subclasses and insertion-time identities/timestamps. Their Objective-C runtime names use the `WITT` prefix even though their Swift and entity names remain domain-native; this prevents global runtime collisions such as the device-only `Container` collision found in TestFlight build 4. Managed objects do not cross into the SwiftUI presentation layer. [`CatalogModels.swift`](../witt/Catalog/CatalogModels.swift) defines immutable, `Sendable` snapshots, destination enums, mutation drafts, repository errors, and the `CatalogRepository` protocol.

[`CoreDataCatalogRepository`](../witt/Catalog/CoreDataCatalogRepository.swift) is the persistence implementation. It owns a background context with transaction author `witt.catalog`; each operation resets that context, fetches the required active graph, validates the mutation, saves atomically, and returns snapshots. Managed-object insertion resolves the entity explicitly, verifies its configured runtime class against the requested type, and constructs that type directly; a model contract error is reported normally instead of relying on Core Data class lookup and a forced cast. Its contract covers catalog reads, initial Home seeding, create/edit, same-Place moves, photo replacement/removal, cascading archive, Thing saving, QR target listing and binding, atomic target creation plus binding, and QR resolution.

New Places are assigned to the private store when CloudKit is active. Descendants, keywords, QR codes, and photos are explicitly assigned to the persistent store containing their Place. This avoids cross-store relationships and ensures edits to a shared Place stay in the shared store. The in-memory configuration uses one local store for tests and previews.

[`CatalogStore`](../witt/App/CatalogStore.swift) is the main-actor application store. It wraps the repository, publishes `[PlaceSnapshot]`, unassigned QR targets, loading/error state, and per-Place sharing state, and reloads after every successful mutation. It also bridges Place sharing because Apple's sharing APIs require the saved managed-object root. Views depend on the store and snapshots, not fetch requests or managed-object lifetimes.

## CloudKit stores, sharing, and change propagation

[`PersistenceController`](../witt/Persistence/PersistenceController.swift) configures `NSPersistentCloudKitContainer` with two SQLite stores when `WITTCloudKitContainerIdentifier` is available:

- `WITT-private.sqlite` maps to the CloudKit private database.
- `WITT-shared.sqlite` maps to the CloudKit shared database.

The configured container is `iCloud.in.sids.witt`, declared in [`Info.plist`](../witt/Info.plist) and [`WITT.entitlements`](../witt/WITT.entitlements). Both store descriptions enable persistent history tracking and remote-change notifications. The view context uses author `witt.app`, automatically merges parent changes, and applies an object-trump merge policy. Repository and history work use named background contexts.

The current Core Data-generated schema was deployed to CloudKit production on July 15, 2026 and independently re-exported to confirm an exact match with development. It contains `CD_Area`, `CD_Container`, `CD_PhotoAsset`, `CD_Place`, `CD_QRCode`, `CD_Room`, `CD_Thing`, and `CD_ThingKeyword`; `CD_PhotoAsset` includes companion `ASSET` fields for both original and thumbnail payloads. `PersistenceController` exposes `--initialize-cloudkit-schema-dry-run` and `--initialize-cloudkit-schema` only in Debug, only when explicitly launched, and only outside XCTest. The container-level call runs once after both synchronous stores load. Release builds contain no schema-initialization path. Future additive model changes must repeat development initialization, review, production deployment, and post-deploy export comparison.

On a remote-store notification, `PersistenceController.processPersistentHistory()` fetches transactions separately for each store after its latest in-process token, ignores transactions authored by the view context, and merges object-ID notifications into the view context. `ContentView` also asks `CatalogStore` to refetch snapshots, so visible state is rebuilt from the current persisted graph. History tokens are currently process-memory state; they are not persisted across launches or used for history pruning.

[`PlaceSharingService`](../witt/Sharing/PlaceSharingService.swift) shares a saved private-store `Place` as the root object. Before creating a `CKShare`, it requires loaded private and shared stores, no unsaved changes, and a reachable graph in which every descendant points back to the same Place. Shares are private to specified recipients, and the system collaboration UI restricts participant permissions to read/write. Existing shares use the same activity surface for participant management. Invitation metadata is accepted explicitly into the shared store.

The architecture assumes complete read/write sharing of a Place, including its photos and QR bindings. Real-device validation remains mandatory because simulator and unit coverage cannot prove CloudKit transfer behavior or account-to-account conflict behavior.

## Photo pipeline and persistence

Camera and photo-library inputs converge on the value types in [`PhotoModels.swift`](../witt/Photos/PhotoModels.swift). [`PhotoNormalizer`](../witt/Photos/PhotoNormalizer.swift) uses Image I/O to apply source orientation, cap the full image's long edge at 2048 pixels, create a 320-pixel thumbnail, encode both as JPEG, and omit source metadata. Default JPEG qualities are 0.82 for the full image and 0.72 for the thumbnail. Normalization occurs off the main actor in both capture adapters.

The current persistence design is an explicit `PhotoAsset` record for each stored photo. It carries full and thumbnail binary payloads, content type, dimensions, byte size, kind, source, timestamps, a required Place relationship, and exactly one owner relationship. `data` and `thumbnailData` use Core Data Binary Data with external storage enabled. The owning object points to its primary photo, while the Place relationship keeps every asset in the Place-rooted CloudKit graph. Replacing or removing a primary photo deletes the superseded asset through a single `PhotoMutation` path.

This is the MVP production candidate, not a temporary file cache. A hybrid payload design is conditional on the real-device sharing spike showing unacceptable transfer reliability, latency, storage pressure, or conflict behavior. If that fallback is needed, `PhotoAsset` remains the stable domain record and owner/Place edge; only payload backing changes to a local-file plus CloudKit-asset strategy. IDs, metadata, thumbnails, migration state, and missing/download-required states should remain explicit so repository and presentation contracts do not need to become file-path APIs. Do not introduce the hybrid complexity without evidence from the sharing spike.

## QR architecture

[`QRToken`](../witt/QR/QRToken.swift) is the exact, non-empty persistence identity of a decoded QR payload. `QRToken.generate()` creates WITT-owned identifiers as canonical 128-bit random values encoded as 22 unpadded base64url characters using `SecRandomCopyBytes`. [`WITTQRCodeURL`](../witt/QR/WITTQRCodeURL.swift) is the strict, versioned envelope for those generated identifiers: `witt://qr/v1/<token>`. `QRToken(scannedPayload:)` unwraps a valid generated WITT URL to its raw token for compatibility with existing rows; every other non-empty scanner payload is preserved exactly. External WITT deep-link parsing still rejects alternate casing/serialization, credentials, ports, query strings, fragments, unknown versions, and noncanonical generated tokens.

`QRCodeResolving` and [`QRCodeResolution`](../witt/QR/QRCodeResolution.swift) isolate token lookup from routing. The repository returns known Area, known Container, unknown, needs-repair, or conflict. Ordinary binding is idempotent only for the same token/target pair; otherwise a token already in storage or a target with an existing bound code is rejected. `createTargetAndBindQRCode` creates or selects the Room and Area, optionally creates or selects a Container, and binds the token in one Core Data transaction.

`CreateAreaDraft` and `CreateContainerDraft` may carry an unused QR token, allowing the target and binding to be saved atomically with its name, detail, photo, and parent. Explicit replacement is also transactional: it accepts an unused token, deletes the target's former QR rows, and binds the new token in the target's persistent store. The former label then resolves as unknown and can be reused. A token attached to any other target is rejected without mutation; WITT never silently moves a binding across targets or Places.

[`QRDeepLinkRouter`](../witt/App/QRDeepLinkRouter.swift) converts known destinations to add-Thing routes and unknown tokens to attach routes. QR identity belongs only to Areas and Containers; Rooms and Things are intentionally outside the binding model.

### Printable PDFs

The printing subsystem in [`QRPrinting`](../witt/QRPrinting) generates random, unique tokens and renders their WITT URLs without inserting unbound rows into Core Data. `QRCodeSheetConfiguration` unifies A4, US Letter, and Custom paper. Built-in papers provide fixed metric dimensions; Custom accepts a width and either fixed height or unlimited length. Independent paper-edge margins, exact label dimensions, and horizontal/vertical gaps determine the grid rather than a manually selected column count. The default configuration models a 100 mm continuous roll with four contiguous 25 × 25 mm square labels across.

[`QRCodeSheetLayout`](../witt/QRPrinting/QRCodeSheetModels.swift) converts millimeters to 72-point PDF units, derives rows and columns while preserving exact physical label frames, rejects nonpositive or nonfitting geometry, and enforces a minimum 20 mm QR side. Fixed paper retains its declared page size. Continuous output derives its height from the actual rows and splits before UIKit's 14,400-point page-height limit, including a correctly shortened final page. Portrait rectangular content is rotated within its physical label so the ID remains beside the QR. [`QRCodeSheetPDFGenerator`](../witt/QRPrinting/QRCodeSheetPDFGenerator.swift) uses Core Image error correction level M, adds a four-module white quiet zone, creates an integer-scaled high-resolution bitmap, and draws with interpolation disabled. Square labels omit all text; rectangular labels draw the eight-character ID beside the QR and optionally add a write-in line below it.

[`QRCodePrintingView`](../witt/QRPrinting/QRCodePrintingView.swift) writes the generated PDF atomically to a temporary URL, previews it with Quick Look, and relies on the native preview share/print actions. The temporary file is removed when preview closes.

## Camera and scanner adapters

Thing photo capture is isolated behind SwiftUI adapters in [`CameraCaptureView.swift`](../witt/Photos/CameraCaptureView.swift) and [`PhotoLibraryPicker.swift`](../witt/Photos/PhotoLibraryPicker.swift). The camera bridge wraps `UIImagePickerController`; library selection uses `PhotosPicker`. Both return `NormalizedPhoto` or a typed error to the flow and neither writes persistence directly. `CameraAuthorizationState` maps AVFoundation authorization and hardware availability into explicit not-determined, authorized, denied, restricted, and unavailable states. Denied and restricted capture surfaces provide Open Settings and Cancel actions; foreground activation rechecks authorization so a newly granted permission resumes the picker.

QR scanning is a separate AVFoundation pipeline. [`QRScannerSession`](../witt/Scanning/QRScannerSession.swift) owns camera input, metadata output, QR-only decoding, the serial session queue, torch changes, and start/stop intent. [`QRScannerView`](../witt/Scanning/QRScannerView.swift) owns permission and lifecycle presentation, pauses for inactive scenes or overlaid flows, updates preview rotation from interface orientation, and reports denied, restricted, unavailable, and failed states explicitly. Denied or restricted access provides Open Settings inside the scanner while its existing Close control remains available; returning to the foreground rechecks authorization before starting the session. `QRScannerPayloadDeduplicator` suppresses repeated reads of the same payload for 1.5 seconds by default and resets when the session stops.

The scanner emits only strings. Payload interpretation, WITT deep-link validation, persistence resolution, and user routing remain outside AVFoundation, which keeps hardware behavior independently testable from QR semantics. In-app routing accepts any non-empty payload and preserves arbitrary identities exactly; only external WITT deep links require the strict versioned URL form. `QRAssignmentScanner` composes the same hardware view for Storage Area and Container creation and replacement, pauses during resolution, accepts an unknown payload or the target's existing identity, and keeps empty, already-attached, repair, and conflict errors local to the scanner.

## AI labeling boundary

[`ThingPhotoLabelingService`](../witt/AI/ThingPhotoLabelingService.swift) is the provider-neutral async boundary from a normalized `PhotoInput` to a `ThingLabelSuggestion`. The service is injected through the SwiftUI environment and used by both known-QR review and manual Thing creation. Suggestions are editable; persisted provenance distinguishes reviewed AI names from user-entered names. Failures fall back honestly to manual entry.

The current Responses-compatible transport, deterministic debug mock, environment configuration, structured-output validation, privacy behavior, and credential constraints are documented in [AI labeling](ai-labeling.md). Provider-specific request details must remain behind the protocol.

## SwiftUI presentation and state

The app uses standard iOS 26 SwiftUI containers and system appearance. `AppShellView` owns app-level navigation and modal state; `CatalogStore` owns loaded catalog state; feature views own short-lived form, query, selection, camera, and progress state. Successful Thing creation returns the exact new snapshot. Both creation paths replace their form with the shared Thing Saved surface, while small dismissal-state values defer scanner presentation and Browse navigation until the active sheet has actually closed.

Browse uses the selected Place's Rooms screen as the root of a `NavigationStack` on iPhone and iPad. Destinations resolve Place, Room, Storage Area, Container, and Thing identifiers against the latest snapshots. Versioned app preferences store the selected Place and deepest canonical destination, where a Place destination represents that Place's Rooms root. Restoration waits for initial catalog loading, selects the destination's active Place, and removes the leading Place route from the visible path. Reloads preserve the deepest screen through parent moves; missing, archived, or cyclic destinations return to the persisted selected Place root, while an unavailable selected Place falls back deterministically to another active Place.

The system toolbar exposes a leading Place menu, full-catalog search, and full-screen Scan QR action. The Place menu uses the `mappin.and.ellipse` SF Symbol, marks the current Place, creates Places, and opens QR-label printing. Compact layouts explicitly group Place, Search, and Scan as three nonoverlapping bottom controls; regular layouts let the system place Search in the top toolbar and keep Place and Scan as separated bottom actions. Search matches active Thing names, keywords, and location components across all Places. Its results replace only the current screen's content so the active search field remains available. Selecting a result reconstructs its current canonical hierarchy and changes the selected Place when needed; cancellation leaves Browse untouched. A successful New Place save returns its actual repository identity so Browse can select it immediately.

Each Place's Rooms screen reads the store's cached CloudKit sharing state to expose system share management contextually. Collection presentations remain domain-specific: Rooms use two-column landscape tiles, Storage Areas use image-led rows, and Things and Containers use two-column square media tiles with restrained text overlays. Descendant counts walk the active snapshot graph and deduplicate Thing identifiers so malformed repeated paths do not inflate totals. Thing details and management forms also resolve current snapshots by ID, so a reload does not leave a view holding a stale managed object. Creation forms use local focus state to focus the primary name field without applying that behavior to edit forms.

Creation and editing are routed through `ManagementRoute` and one-screen forms in [`Features/Management`](../witt/Features/Management). Draft state is converted to typed repository mutations only on commit. New Storage Area and Container forms can hold a scanned unused token until the complete draft is saved atomically. Context-aware destination choices are derived from the active Place graph; Container choices exclude the edited Container and its descendants. Archive confirmation copy uses computed subtree impact. Unknown QR attachment uses dedicated state in [`AttachQRCodeView.swift`](../witt/Features/Scan/AttachQRCodeView.swift), showing unassigned Areas and Containers first and falling through to the atomic create-and-bind flow.

## Testing seams and baseline

The `wittTests` target currently passes 160 tests in Debug and 156 in Release-optimized configuration. Four Debug-only tests cover the opt-in CloudKit schema launch-argument contract. The baseline covers:

- pure containment, same-Place ownership, and Container-cycle validation;
- Core Data creation, edits, moves, archive cascades, snapshots, store placement, and QR mutations;
- managed-object runtime class mappings, build-4 schema hashes, controlled model-contract failures, and SQLite Container reopen compatibility;
- QR token/URL parsing, resolution, routing, duplicate scanner payloads, scanner state transitions, and denied/restricted authorization recovery;
- fixed-sheet and continuous-roll label geometry, physical margins/gaps, square and rectangular content rules, pagination, PDF dimensions, quiet zones, crisp rendering, and failure paths;
- camera authorization mapping and recovery policy, plus photo orientation, resizing, metadata stripping, thumbnail generation, and persistence;
- AI protocol mocks, Responses-compatible request/response handling, configuration selection, and error mapping;
- management preselection, AI suggestion application, post-save dismissal handoffs, exact destination reconstruction, archive facts, catalog presentation, and Place-sharing helpers.

Primary seams are `CatalogRepository`, `QRCodeResolving`, `ThingPhotoLabelingService`, `PhotoNormalizer`, QR token/image generator closures, pure layout/validation types, in-memory `PersistenceController`, and immutable snapshots. Hardware camera behavior, CloudKit service behavior, UIKit sharing UI, and true multi-account synchronization require device or integration testing beyond this unit baseline.

## Production boundaries and release gates

The implemented app shell, repository, photo pipeline, scanner, QR printing, sharing UI, and AI transport are integrated. Production readiness still depends on evidence at external-system boundaries:

1. Complete the real-device, two-iCloud-account Place-sharing spike. Verify invitation acceptance, initial full graph transfer, read/write edits in both directions, nested containment, archive propagation, and conflict behavior.
2. Specifically validate full and thumbnail `PhotoAsset` binary transfer, offline creation followed by sync, replacement/removal, larger catalogs, launch/reload latency, and device storage behavior. Choose the hybrid fallback only if this evidence requires it.
3. Put AI behind a WITT-owned relay or another short-lived credential mechanism. Never ship a long-lived provider API key in the app bundle. Select the production model, endpoint policy, retention/privacy disclosures, failure budget, and user-facing consent posture before enabling live labeling.
4. Keep future CloudKit model changes additive and repeat schema initialization/deployment verification. Continue validating push delivery and migration behavior; build 7 signing and the current production schema are verified.
5. Run device coverage for camera permission transitions, QR focus/rotation/torch behavior, deep-link launch from a cold app, photo capture memory pressure, iPad presentation, physical A4/Letter printing, and representative thermal printers.
6. Preserve the 155-test Debug and 151-test Release-optimized baselines and add focused regression coverage for any release-gate fixes. Run the suite with Release optimization and `ENABLE_TESTABILITY=YES` before TestFlight uploads, in addition to the ordinary Debug baseline. Treat [todo.md](todo.md) as the authority for current TestFlight gates and completion state rather than copying a live backlog into this document.

These gates are validation and production-operations work, not a request to reopen settled domain boundaries. Place-rooted ownership, explicit Area/Container QR binding, provider-neutral AI, normalized photo inputs, and snapshot-based presentation remain the architectural constraints.
