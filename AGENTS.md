# WITT Agent Brief

WITT means "Where Is The Thing?" This repo is for a native iOS app that helps people catalogue items in storage areas around a home or other place so they can later answer, quickly and confidently, where an item is.

The human product manager is Sid. Treat this project as product-led: clarify user workflows, preserve product decisions, and keep implementation threads aligned with the product brief instead of letting the code drift into generic inventory software.

## Source Context

The `docs/` directory is the canonical home for WITT product, architecture, planning, status, and release documentation. Start with `docs/README.md`, then read the documents relevant to the task.

Primary context:

- `docs/product.md` - product language, workflows, scope, and UX direction.
- `docs/architecture.md` - implementation-grounded architecture and production boundaries.
- `docs/ai-labeling.md` - provider-neutral AI contract and security/privacy constraints.
- `docs/status.md` - current implementation and verification snapshot.
- `docs/release.md` - durable distribution facts and release process.
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
2. QR codes use `witt://` URLs so scanning opens the app directly.
3. The app should generate a printable PDF grid of random QR codes.
4. Scanning an unassociated QR code should offer to bind it to an existing or new area/container.
5. Scanning a known QR code should open the add-item flow: take a photo, immediately use AI to label and keyword it, then let the user review, edit, and save.
6. Things do not need QR codes for the MVP.
7. Rooms do not need QR codes for now.

AI is expected for photo understanding, item labeling, and keyword/tag generation. Assume an OpenAI-compatible API, but keep provider details isolated so the implementation can change later.

## Technical Direction

Build as a native iOS app with SwiftUI. UIKit is acceptable for tricky platform integration where SwiftUI is not enough.

Minimum supported OS is iOS 26.

Support iPhone and iPad.

Use Core Data with iCloud sharing for persistence. Sharing should happen at the place level, with complete read/write access for shared participants.

The repo now contains the sixth integrated implementation milestone:

- The Browse, Search, Thing detail, known-QR add Thing, and unknown-QR attach/create flows now use immutable snapshots from `CoreDataCatalogRepository`; `DemoInventoryStore` has been removed.
- Browse opens by default and presents one current Place with switching and creation, Place-local edit/share actions, useful empty states, and contextual New Room, Storage Area, Container, and Thing controls. Familiar QR and pencil toolbar actions stay explicit instead of collapsing into ellipsis menus.
- Real AVFoundation QR scanning handles permissions, lifecycle, torch state, orientation, and duplicate suppression. Scanned known destinations and unknown tokens are preserved through routing.
- Camera and Photos picker adapters normalize orientation, strip metadata, cap full images at 2048 px, create 320 px thumbnails, and persist explicit `PhotoAsset` records.
- The confirmed `iCloud.in.sids.witt` container, iCloud/remote-notification entitlements, private/shared Core Data stores, Place-rooted read/write sharing UI, and invitation acceptance are wired.
- The one-screen create-and-attach flow can atomically create or select a Room, Storage Area, and Container before binding a scanned QR code.
- Printable random QR sheets support A4, US Letter, and configurable continuous Thermal Roll layouts with metric width, QRs per row, spacing, margins, geometry validation, two label styles, crisp high-contrast codes, Quick Look preview, and the native share/print flow without persisting unbound tokens.
- Explicit repository and store contracts cover manual create, edit, same-Place move, photo replacement/removal, and cascading archive for Place, Room, Storage Area, Container, and Thing. Native one-screen management forms, context-aware add menus, live detail navigation, archive confirmations, and iPhone/iPad Browse integration are implemented.
- A Responses-compatible vision adapter validates normalized JPEGs, requests strict structured suggestions with provider storage disabled, maps transport/provider failures, and is injected into both Thing-creation paths. Runtime configuration is environment-only through `WITT_AI_RESPONSES_URL`, `WITT_AI_MODEL`, and `WITT_AI_BEARER_TOKEN`; no provider secret belongs in the app bundle. Debug builds use the deterministic mock only when no AI configuration is present, while unconfigured release builds fail honestly into manual entry.
- The `wittTests` target has 102 passing simulator tests covering persistence, containment and management mutations, QR routing/scanning/printing and thermal geometry, photo normalization, AI transport and management-form helpers, presentation behavior, and Place sharing helpers.

The production UI and AI transport seam are integrated. Live AI activation still requires a WITT-owned relay or another secure short-lived credential strategy, plus a chosen model and privacy policy; never ship a long-lived provider API key in the iOS app. The next product-critical validation is the real-device, two-iCloud-account sharing spike, especially `PhotoAsset` binary transfer and bidirectional edits.

Version 1.0 build 2 is available through the `WITT Internal` TestFlight group for Sid's next device review. Put all review feedback into [`docs/todo.md`](docs/todo.md) before dispatching fixes.

## Working Model For Codex Threads

This thread acts as project manager unless Sid says otherwise.

When launching implementation or research work in separate Codex threads:

1. Use the `/Users/sid/src/witt` project.
2. Default to Medium thinking.
3. Increase thinking for architecture, Core Data/iCloud sharing, deep linking, camera/QR scanning, and security-sensitive work.
4. Decrease thinking for narrow mechanical tasks, formatting, or small copy changes.
5. Give each worker a tight brief with:
   - the product goal,
   - relevant files,
   - expected deliverable,
   - verification required,
   - instruction to preserve unrelated user changes.
6. Ask workers to update the relevant file under `docs/` when their work changes durable product, architecture, status, release, or planning context.
7. Read thread results before integrating or assigning dependent work.
8. Add significant new documents to `docs/README.md`; remove superseded plans and proposals instead of maintaining historical duplicates.
9. Use `docs/todo.md` as the only live backlog. Add incoming feedback to its inbox, move triaged work into a priority section, and update task state after implementation and verification.

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
