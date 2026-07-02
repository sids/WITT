# WITT Agent Brief

WITT means "Where Is The Thing?" This repo is for a native iOS app that helps people catalogue items in storage locations around a home so they can later answer, quickly and confidently, where an item is.

The human product manager is Sid. Treat this project as product-led: clarify user workflows, preserve product decisions, and keep implementation threads aligned with the product brief instead of letting the code drift into generic inventory software.

## Source Context

Primary product note: Bear note titled `WITT: Where Is The Thing?`.

Bear is the canonical home for WITT project docs. Every durable WITT product, planning, research, or decision note in Bear must be tagged `#projects/WITT`. Prefer titles beginning with `WITT:`. The project docs index is the Bear note titled `WITT: Project Docs Index`.

Use `bearcli` to read it when product context may have changed:

```sh
bearcli search '@title WITT: Where Is The Thing?' --format json --fields all
bearcli cat <note-id> --format json
```

Use this to list project docs:

```sh
bearcli search '#projects/WITT' --format json --fields all
```

In this environment `bearcli` may need permissions outside the repo sandbox because the note lives in Bear's local app storage.

## Product Shape

WITT catalogues "things" at home.

Core hierarchy:

1. Properties contain rooms.
2. Rooms contain locations.
3. Locations and rooms may contain containers.
4. Things live in containers, locations, or rooms.
5. Photos should be stored for locations, containers, and things.

QR codes are central to the experience:

1. QR codes are associated with areas and containers.
2. QR codes use `witt://` URLs so scanning opens the app directly.
3. The app should generate a printable PDF grid of random QR codes.
4. Scanning an unassociated QR code should offer to bind it to an existing or new location/container.
5. Scanning a known QR code should open the add-item flow: take a photo, use AI to label and keyword it, then let the user edit/confirm.

AI is expected for photo understanding, item labeling, and keyword/tag generation. Assume an OpenAI-compatible API, but keep provider details isolated so the implementation can change later.

## Technical Direction

Build as a native iOS app with SwiftUI. UIKit is acceptable for tricky platform integration where SwiftUI is not enough.

Use Core Data with iCloud sharing for persistence. Sharing should happen at the property level, with complete read/write access for shared participants.

The repo currently contains a minimal Xcode project:

```text
witt.xcodeproj
witt/ContentView.swift
```

The current app entry point is still a placeholder "Hello, world!" SwiftUI app. Expect major product, model, navigation, and persistence work ahead.

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
6. Ask workers whose output should become durable project documentation to provide a Bear-ready title and summary.
7. Read thread results before integrating or assigning dependent work.
8. Store durable project docs in Bear with `#projects/WITT` and update `WITT: Project Docs Index` when adding a significant note.

Prefer worktree threads for substantive code changes so efforts stay isolated. Use local project threads for quick read-only research or small repo inspection tasks.

## Engineering Expectations

Follow existing repo structure and Swift/Xcode conventions. Keep changes scoped to the assigned feature or investigation.

Do not revert user changes. The working tree may contain local Xcode user-data changes, especially under `witt.xcodeproj/xcuserdata/`.

For iOS build/run/test work, prefer the XcodeBuildMCP tools when available. Before the first simulator build/run/test in a thread, check session defaults as required by those tools.

When adding app code:

1. Keep domain concepts explicit: `Property`, `Room`, `Location`, `Container`, `Thing`, and `QRCode` should remain easy to reason about.
2. Avoid prematurely generic inventory abstractions.
3. Keep AI service boundaries mockable and provider-agnostic.
4. Treat iCloud sharing and local persistence as product-critical, not an afterthought.
5. Design QR and deep-link flows around real-world repeated use while moving around a home.

## UX Principles

WITT should feel fast and practical during physical cataloging sessions. Optimize for scanning, taking photos, confirming AI suggestions, and moving on.

The app should support messy real homes: nested containers, ambiguous locations, duplicate-looking things, and later edits.

Avoid heavy onboarding or marketing-style screens in the product surface. The first useful experience should help the user create or enter a property, scan/attach a QR code, or find/add a thing.

## Open Product Questions

Clarify these with Sid before locking implementation:

1. Whether a "property" means a home only, or can also mean office/storage unit/etc.
2. Whether things can belong to multiple locations conceptually, or only have one current physical location.
3. Whether QR codes identify only locations/containers, or can also identify individual things.
4. Whether photo storage should use Core Data external binary storage, CloudKit assets, local files referenced from Core Data, or another approach.
5. Whether AI labeling should run immediately after capture, batched later, or both.
6. What minimum supported iOS version and device classes are intended.
