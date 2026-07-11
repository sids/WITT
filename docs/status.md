# WITT Implementation Status

WITT is at the sixth integrated implementation milestone. The native SwiftUI app supports iPhone and iPad on iOS 26 and uses Core Data with private and shared CloudKit stores.

## Integrated Capabilities

- Browse, Search, Thing detail, known-QR add-Thing, and unknown-QR attach/create flows use immutable snapshots from `CoreDataCatalogRepository`.
- Browse opens by default with Place switching and creation, Place-local edit and share actions, contextual creation controls, useful empty states, and live detail navigation.
- AVFoundation QR scanning handles permissions, lifecycle, torch state, orientation, duplicate suppression, known destinations, and unknown tokens.
- Camera and Photos picker input is normalized, stripped of metadata, resized, thumbnailed, and stored as explicit `PhotoAsset` records.
- Place-rooted CloudKit sharing includes private/shared stores, read/write participant sharing UI, and invitation acceptance.
- Unknown QR codes can be attached in one flow while selecting or creating a Room, Storage Area, and optional Container.
- Printable random QR sheets support A4, US Letter, and configurable thermal rolls, with validated geometry, labels, preview, share, and print.
- Place, Room, Storage Area, Container, and Thing support create, edit, same-Place move, photo replacement/removal, and cascading archive through explicit repository contracts and native management forms.
- A provider-isolated, Responses-compatible vision adapter supplies structured Thing labels and keywords in both Thing-creation paths.

## Production Boundaries

The production UI and AI transport boundary are integrated. Live AI still requires a WITT-owned relay or another secure short-lived credential strategy, a selected model, and an approved privacy policy. Long-lived provider credentials must never ship in the app bundle.

The next product-critical validation is real-device sharing between two iCloud accounts, particularly `PhotoAsset` binary transfer and bidirectional edits. Active work and TestFlight feedback belong only in [todo.md](todo.md); this page is not a backlog.

## Verification And Distribution

The baseline is 102 passing `wittTests` simulator tests covering persistence, containment and management mutations, QR routing, scanning and printing, thermal geometry, photo normalization, AI transport, management-form helpers, presentation behavior, and Place sharing helpers.

Version 1.0 build 2 is available to the `WITT Internal` TestFlight group. See [release.md](release.md) for durable release facts and process.

## Project Documents

- [Documentation index](README.md)
- [Product brief](product.md)
- [Architecture](architecture.md)
- [AI labeling](ai-labeling.md)
- [Todo tracker](todo.md)
- [Release](release.md)
