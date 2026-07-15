# WITT Agent Brief

WITT means "Where Is That Thing?" This repo is for a native iOS app that helps people catalogue items in storage areas around a home or other place so they can later answer, quickly and confidently, where an item is.

The human product manager is Sid. Treat this project as product-led: clarify user workflows, preserve product decisions, and keep implementation threads aligned with the product brief instead of letting the code drift into generic inventory software.

## Source Context

The `docs/` directory is the canonical home for WITT product, architecture, planning, status, and release documentation. Start with `docs/README.md`, then read the documents relevant to the task.

Primary context:

- `docs/product.md` - product language, workflows, scope, and UX direction.
- `docs/architecture.md` - implementation-grounded architecture and production boundaries.
- `docs/ai-labeling.md` - provider-neutral AI contract and security/privacy constraints.
- `docs/ai-production.md` - unwired relay/auth boundary, evaluation gates, and rollout safeguards.
- `docs/product-decisions.md` - version 1 recommendations awaiting Sid's acceptance.
- `docs/status.md` - current implementation and verification snapshot.
- `docs/release.md` - durable distribution facts and release process.
- `docs/app-store.md` - App Store metadata, privacy mapping, and screenshot runbook.
- `docs/app-icon-concepts.md` - production icon directions and the post-approval workflow.
- `docs/todo.md` - the only live backlog and TestFlight feedback inbox.

Capture every new issue or product comment in `docs/todo.md`, keep its priority and acceptance criteria current, and mark it complete only after verification. Do not create or maintain WITT project docs in Bear; the former Bear notes are archived historical material.

## Product Shape

WITT catalogues "things" at home.

Core hierarchy:

1. Places contain rooms.
2. Rooms contain areas. `Area` is the model term; use `Storage Area` in user-facing copy when the extra clarity helps.
3. Areas and rooms may contain containers.
4. Things live in exactly one current container, area, or room.
5. Photos should be stored for places, areas, containers, and things. Places should have a name and may have an optional photo.
6. For MVP photo persistence, use explicit `PhotoAsset` records with Core Data Binary Data configured for external storage. The goal is for photos to remain part of the Core Data object graph mirrored/shared by `NSPersistentCloudKitContainer` when a Place is shared. Keep the model compatible with a later hybrid local-file/CloudKit-asset design if the sharing spike shows the MVP approach is insufficient.

QR codes are central to the experience:

1. QR codes are associated with areas and containers.
2. The in-app scanner accepts any QR code with a non-empty payload. WITT-generated labels use versioned `witt://` URLs so scanning them outside the app can launch WITT directly.
3. The app should generate a printable PDF grid of random QR codes.
4. Scanning an unassociated QR code should offer to bind it to an existing or new area/container.
5. Scanning a known QR code should open the add-item flow: take a photo, immediately use AI to label and keyword it, then let the user review, edit, and save.
6. Things do not need QR codes for the MVP.
7. Rooms do not need QR codes for now.
8. New Storage Areas and Containers may scan an unused QR code before saving. Existing targets attach or reattach from their ellipsis menu. For the first release, each Storage Area or Container has exactly one active QR and each payload has exactly one active target. Reattaching replaces that target's former binding and releases the old label, but must never take a healthy code attached elsewhere.
9. Scanning a damaged or multiply bound payload opens Repair QR directly. Repair may consolidate the payload onto an eligible existing target, atomically create and bind a new target, or explicitly replace the current target's code from its contextual Reattach action. General repair never takes a different healthy binding.

AI is expected for photo understanding, item labeling, and keyword/tag generation. Assume an OpenAI-compatible API, but keep provider details isolated so the implementation can change later.

## Technical Direction

Build as a native iOS app with SwiftUI. UIKit is acceptable for tricky platform integration where SwiftUI is not enough.

Minimum supported OS is iOS 26.

Support iPhone and iPad.

Use Core Data with iCloud sharing for persistence. Sharing should happen at the place level, with complete read/write access for shared participants.

The repo now contains the eighth integrated implementation milestone:

- The Browse, Search, Thing detail, known-QR add Thing, and unknown-QR attach/create flows now use immutable snapshots from `CoreDataCatalogRepository`; `DemoInventoryStore` has been removed.
- Browse opens directly on the selected Place's Rooms screen; there is no Places screen or tab bar. A Mail-style system toolbar uses `mappin.and.ellipse` for the Place menu, full-catalog system search, and a trailing Scan QR action that presents the camera full-screen and closes back to the unchanged Browse position. The Place menu switches or creates Places. Rename Place and Share Place live in the Rooms screen's ellipsis menu, followed by a divider and Print QR Labels; an already-shared Place also shows a separate Shared management button immediately before that menu. Room screens likewise keep Edit Room under an ellipsis menu instead of exposing a standalone pencil button. Contextual New Room, Storage Area, Container, and Thing controls remain in their owning screens. New Room, Thing, and Container actions are tint-matched dashed cells inside their corresponding grids. New Storage Area is a fully rounded standalone dashed row when the Room has none; in a populated list it becomes the transparent attached final row with a native separator above it and no dashed top edge. Its one-point tint sides align with the full width of the native rows above, while a full-width circular stroke-border contour keeps both rounded bottom corners and the dashed bottom edge visible inside the List mask. The same-path corner reinforcement uses a restrained 1.5-point optical weight so antialiasing does not make the curves look paler than the straight border. Storage Area screens use a native Things/Containers segmented control, defaulting to Things and showing only the selected collection and its New tile. The selected Place and deepest Browse destination persist across launches and are restored through the current active hierarchy after catalog loading; missing, archived, or cyclic destinations restore safely to an active Place root, while an explicit Room tap replaces any stale restored path. Browse collections use distinct layouts: two-column landscape Room tiles, image-led Storage Area rows, and low-margin two-column square Thing and Container photo tiles. Room, Storage Area, and Container counts include active descendant Things.
- Real AVFoundation QR scanning handles permissions, lifecycle, torch state, orientation, and duplicate suppression. Denied access offers Open Settings, restricted and unavailable states remain explicit, and returning from Settings rechecks authorization before scanning resumes. Scanned known destinations and unknown tokens are preserved through routing; manual QR payload entry is deferred from the first release.
- Camera capture uses the same denied/restricted/unavailable recovery model, with Open Settings and Cancel actions. Camera and Photos picker adapters normalize orientation, strip metadata, cap full images at 2048 px, create 320 px thumbnails, and persist explicit `PhotoAsset` records. Photo-library normalization is lifecycle-bound, prevents overlapping selection, cooperates with cancellation, and suppresses stale callbacks after dismissal or replacement.
- The confirmed `iCloud.in.sids.witt` container, iCloud/remote-notification entitlements, private/shared Core Data stores, Place-rooted read/write sharing UI, and invitation acceptance are wired. The complete eight-record-type Core Data schema was deployed to production and independently re-exported on July 15, 2026, including exact full/thumbnail `PhotoAsset` asset mappings. Debug-only opt-in launch arguments support future schema dry runs and initialization; release builds contain no initializer.
- The one-screen create-and-attach flow can atomically create or select a Room, Storage Area, and Container before binding a scanned QR code.
- New Storage Area and Container forms can scan and atomically bind any unused QR code with a non-empty payload. Existing target screens use a shared full-screen scanner for Attach/Reattach; replacement releases the former label while refusing healthy codes attached elsewhere. Main scans and external WITT links route damaged or conflicting rows directly into Repair QR, which preserves the payload and issue, offers eligible current and unassigned targets plus Create & Attach, and consolidates repairable rows to exactly one binding. Contextual repair can explicitly replace the chosen target's former healthy code after confirmation. Arbitrary payloads preserve exact identity, valid generated WITT URLs remain compatible with legacy raw-token rows, and QR status is not shown in the content layer.
- QR resolution is read-only. The deployed optional `QRCode.lastScannedAt` field remains inert solely for additive Core Data/CloudKit compatibility; runtime code neither reads nor writes scan recency, and legacy values remain untouched.
- Printable random QR labels support A4, US Letter, and Custom paper. Built-in dimensions are automatic; Custom accepts metric width and fixed or unlimited length. Four paper margins, exact label width/height, and horizontal/vertical gaps derive the grid. Custom defaults to the linked 100 mm four-up roll with contiguous 25 × 25 mm square labels. Square labels render QR-only; rectangular labels put the short ID beside the QR and can add a write-in line below it. Output remains dimensionally validated, high contrast, Quick Look previewable, shareable/printable, and does not persist unbound tokens.
- Explicit repository and store contracts cover manual create, edit, same-Place move, photo replacement/removal, and cascading archive for Place, Room, Storage Area, Container, and Thing. Native one-screen management forms, context-aware add menus, live detail navigation, archive confirmations, and iPhone/iPad Browse integration are implemented.
- Core Data entity and Swift names remain domain-native, while every managed-object Objective-C runtime name is WITT-prefixed to avoid global class collisions. Repository insertion validates the entity-to-type contract and constructs the requested type directly, so model mismatches become controlled errors rather than Core Data aborts. Build-4 entity hashes are pinned to prove store compatibility.
- A Responses-compatible vision adapter validates normalized JPEGs, requests strict structured suggestions with provider storage disabled, maps transport/provider failures, and is injected into both Thing-creation paths. Runtime configuration is environment-only through `WITT_AI_RESPONSES_URL`, `WITT_AI_MODEL`, and `WITT_AI_BEARER_TOKEN`; no provider secret belongs in the app bundle. Thing fields remain editable and Save follows normal form validity while analysis is pending or unavailable. Late suggestions fill only untouched fields, and stale results after save, dismissal, replacement, or removal are ignored. Debug builds use the deterministic mock only when no AI configuration is present, while unconfigured release builds fail honestly into manual entry.
- An unwired production relay client and deterministic evaluation scorer define the next AI boundary without activating it. The client requires an exact HTTPS endpoint and short-lived scoped credential, uses ephemeral no-cache/no-cookie transport, rejects redirects, bounds correlated JSON responses, and leaves model/prompt selection to the relay. The committed evaluation fixture is synthetic; live AI still requires the operated relay/auth service, a consented representative photo corpus, privacy approval, and accepted quality/latency gates.
- Thing creation now ends on one shared native Thing Saved surface in both known-QR and contextual flows. Add Another Here retains the exact destination, while Scan Next, View Thing, and Done defer their scanner/navigation handoff until the active sheet has dismissed. `CatalogStore.saveThing` returns the exact saved snapshot for identity-safe routing.
- Browse grids adapt to one column at accessibility Dynamic Type sizes, Review Thing photos expose explicit VoiceOver labels, and QR-paper numeric controls retain stable labels and scalable widths.
- The `wittTests` target has 184 passing simulator tests in Debug and 180 in Release-optimized configuration. Four Debug-only tests cover the opt-in CloudKit schema launch-argument contract; the initializer and those tests are absent from Release. Remaining coverage includes persistence, runtime class mappings and build-4 schema compatibility, containment and management mutations, selected-Place Browse restoration, explicit Room-path replacement and descendant counts, deferred scanner and post-save handoffs, exact saved-Thing destination routing, arbitrary and generated QR identity compatibility, atomic QR creation/replacement/repair and takeover refusal, inert legacy scan timestamps, QR routing/scanning/printing and fixed/continuous physical label geometry, camera permission mapping and recovery, photo normalization and picker lifecycle, AI transport, relay safeguards and deterministic evaluation, adaptive presentation behavior, manual-edit-preserving management-form helpers, and Place sharing helpers.

The production UI and AI transport seam are integrated. Live AI activation still requires a WITT-owned relay or another secure short-lived credential strategy, plus a chosen model and privacy policy; never ship a long-lived provider API key in the iOS app. The next product-critical validation is the real-device, two-iCloud-account sharing spike, especially `PhotoAsset` binary transfer and bidirectional edits.

Version 1.0 build 7, sourced from commit `d723e9e`, is `IN_BETA_TESTING` through the `WITT Internal` TestFlight group with auto-notify enabled. It includes arbitrary QR payload support and the latest Browse creation-control polish, and supersedes build 6. Its App Store Connect build ID is `9d5cf61b-cd1a-40bb-b198-0c62cf2254c3`; Sid confirmed on July 15, 2026 that Container creation, persistence, reopening, and relaunch all succeed on the iPhone affected by the build-4 crash, completing FB-024. Put all review feedback into [`docs/todo.md`](docs/todo.md) before dispatching fixes.

## Working Model For Codex Threads

This thread acts as project manager unless Sid says otherwise.

When launching implementation or research work in separate Codex threads:

1. Use the `/Users/sid/src/witt` project.
2. Default to Medium thinking.
3. Use only Light, Medium, or High thinking for subagents; do not select any other reasoning level.
4. Increase thinking for architecture, Core Data/iCloud sharing, deep linking, camera/QR scanning, and security-sensitive work.
5. Decrease thinking for narrow mechanical tasks, formatting, or small copy changes.
6. Give each worker a tight brief with:
   - the product goal,
   - relevant files,
   - expected deliverable,
   - verification required,
   - instruction to preserve unrelated user changes.
7. Ask workers to update the relevant file under `docs/` when their work changes durable product, architecture, status, release, or planning context.
8. Read thread results before integrating or assigning dependent work.
9. Add significant new documents to `docs/README.md`; remove superseded plans and proposals instead of maintaining historical duplicates.
10. Use `docs/todo.md` as the only live backlog. Add incoming feedback to its inbox, move triaged work into a priority section, and update task state after implementation and verification.
11. For UI work, capture simulator screenshots after integration and share them with Sid in the project-manager thread before considering the work complete. Include every materially changed screen, relevant empty and populated states, and iPhone/iPad evidence when the layouts differ. Screenshots are review artifacts, not a substitute for build and test verification.

Prefer worktree threads for substantive code changes so efforts stay isolated. Use local project threads for quick read-only research or small repo inspection tasks.

## Engineering Expectations

Follow existing repo structure and Swift/Xcode conventions. Keep changes scoped to the assigned feature or investigation.

Do not revert user changes. The working tree may contain local Xcode user-data changes, especially under `witt.xcodeproj/xcuserdata/`.

For iOS build/run/test work, prefer the XcodeBuildMCP tools when available. Before the first simulator build/run/test in a thread, check session defaults as required by those tools.

When adding app code:

1. Keep domain concepts explicit: `Place`, `Room`, `Area`, `Container`, `Thing`, and `QRCode` should remain easy to reason about.
2. Avoid prematurely generic inventory abstractions.
3. Keep AI service boundaries mockable and provider-agnostic.
4. Treat iCloud sharing and local persistence as product-critical, not an afterthought.
5. Design QR and deep-link flows around real-world repeated use while moving around a home.

## UX Principles

WITT should feel fast and practical during physical cataloging sessions. Optimize for scanning, taking photos, confirming AI suggestions, and moving on.

The app should support messy real places: nested containers, ambiguous storage areas, duplicate-looking things, and later edits.

Avoid heavy onboarding or marketing-style screens in the product surface. The first useful experience should support the QR-first flow: scan/attach a QR code, bind it if needed, or add a thing from a known code.

Use the native iOS 26 system appearance. Build with standard SwiftUI structures and controls, such as `NavigationStack`, `NavigationSplitView`, `TabView`, toolbars, sheets, forms, search, and buttons, and let the operating system apply Liquid Glass automatically. Do not add custom glass backgrounds, blur materials, translucent capsules, borders, `.glassEffect`, or glass button styles by default. Custom Liquid Glass is exceptional: consider it only when a standard component cannot express an essential top-level floating control, and confirm the choice with Sid first.

Keep Liquid Glass out of the content layer. Express hierarchy through layout, grouping, typography, imagery, and restrained system tint rather than decoration. WITT should feel like a classy, practical native utility, with calm list, form, camera, and detail surfaces. A scan-QR action can take the role often used by compose buttons in mail apps, but it should still use the standard system control and placement.

For unknown QR scans, avoid unnecessary intermediate steps. Open the attach-QR screen directly. That screen should immediately show unassigned Storage Areas and Containers grouped by type. If there are no suitable unassigned targets, show a create/bind flow that starts from Room selection or creation, then Storage Area selection or creation, then either attach the QR to the selected Storage Area or select/create a Container. Do not introduce QR binding for Rooms or Things.

## Active Work

Do not maintain a second backlog in this file. Read `docs/todo.md` for current TestFlight feedback, release gates, product decisions, engineering work, and deferred ideas. When this file and the tracker disagree about task status or priority, the tracker wins; settled product and architecture constraints in this file still apply.
