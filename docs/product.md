# WITT Product

WITT means "Where Is The Thing?" It is a native iOS app for people who need to catalogue belongings across a home or another real-world place and later answer, quickly and confidently, where an item is. It is designed for individuals, households, and trusted collaborators working in messy storage environments with nested containers, similar-looking things, and locations that change over time.

## Product Vocabulary

- **Place:** The top-level catalogue and sharing boundary, such as a home. A Place has a name and may have a photo.
- **Room:** A named part of a Place. Rooms contain Storage Areas and may directly contain Containers and Things.
- **Area:** The model term for a location within a Room. Use **Storage Area** in user-facing copy when it is clearer, such as "hall closet" or "garage shelf."
- **Container:** A box, bin, drawer, bag, or similar holder. A Container belongs to a Room, Storage Area, or another Container.
- **Thing:** An item the user wants to find. A Thing has exactly one current location: a Room, Storage Area, or Container.

The containment hierarchy is:

```text
Place
  Room
    Storage Area
      Container
        Container
        Thing
      Thing
    Container
      Thing
    Thing
```

## Locked Scope Decisions

- WITT is a practical home-cataloguing product, not generic warehouse or business inventory software.
- Browse, search, editing, QR routing, and sharing operate on persistent catalogue data, not demo content.
- Photos are supported for Places, Storage Areas, Containers, and Things. Thing capture accepts the camera or photo library.
- QR codes use `witt://` links and attach only to Storage Areas and Containers. Rooms and Things do not receive QR codes in the MVP.
- The current attach flow offers targets without an active QR. Whether WITT should support multiple active QR codes per target remains a product decision in [todo.md](todo.md).
- Things always have one current location and can be moved within the same Place.
- Containers may be nested. Archiving a parent archives its contained catalogue branch after confirmation.
- Sharing is rooted at the Place and grants invited participants complete read/write collaboration for that Place.
- AI assists with photo understanding, but the user remains responsible for reviewing the saved record.
- The app supports iPhone and iPad and requires iOS 26.

## QR-First Cataloguing

The Scan tab is a first-class entry point for repeated cataloguing while moving around a home. WITT scans real QR codes and also handles `witt://` links opened outside the scanner.

### Known QR

Scanning a code already attached to a Storage Area or Container opens Add Thing for that destination. WITT offers the camera immediately, also permits choosing a photo, then analyzes the image and opens Review Thing. The user reviews or edits the proposed name, comma-separated keywords, and notes, confirms the location, and saves. If AI is unavailable, the flow remains usable with honest error messaging and manual entry.

### Unknown QR

Scanning an unassigned code opens Attach QR directly. WITT first lists Storage Areas and Containers that do not already have a QR, grouped by type and labeled with their location paths. The user can attach in one step.

When no suitable target exists, or the user chooses Create & Attach, one screen supports selecting or creating the Place context, Room, and Storage Area, then attaching to that Storage Area or selecting or creating a Container. Creation and attachment succeed as one operation. There is no intermediate QR explanation screen and no option to bind the code to a Room or Thing.

## Browse And Creation

Browse opens by default and shows one current Place. The Place header supports switching Places, creating a Place, and explicit edit and share actions. The QR-label action and familiar pencil edit actions remain visible toolbar controls.

On iPhone, Browse navigates from the current Place through Rooms, Storage Areas, Containers, and Things. On iPad, it uses a split view with Rooms in the sidebar and the selected Room in the detail area. Empty states provide the next useful creation action.

Creation is contextual:

- A Place offers New Room.
- A Room offers New Storage Area and displays Things and Containers located directly in the Room.
- A Storage Area offers New Container or New Thing.
- A Container offers New Container or New Thing, including nested Containers.
- Management forms support create, edit, same-Place move, photo replacement or removal, and archive with impact confirmation.

## Find Loop

Find is a dedicated search tab. Before a query, it lists all active Things. Search matches Thing names, keywords, and every component of the location path. A result shows the Thing and its location; opening it shows the photo, full location, keywords, and notes, with an edit action. The core loop is simple: search for what you remember, recognize the Thing, read where it is, and navigate the physical hierarchy if more context is needed.

## Printable QR Labels

WITT generates random, unassigned QR codes as a printable PDF. Generating a sheet does not persist or reserve those tokens; a code becomes part of the catalogue only when it is scanned and attached.

- **A4 and US Letter:** Fixed grid layouts with 6 to 60 labels in increments of six.
- **Thermal Roll:** A continuous layout with 1 to 120 labels and configurable metric paper width, one to four QRs per row, row and column spacing, horizontal margins, and top and bottom margins.
- **Labels:** Choose a short Code ID or a write-in line.
- **Output:** Codes are crisp, high contrast, and validated to remain scannable. The app previews the PDF with Quick Look, then uses the native share and print flow.

## Sharing

A Place is the complete collaboration boundary. Its Rooms, Storage Areas, Containers, Things, QR associations, and photos are expected to travel together through iCloud sharing. Owners can create or manage a Place share, invite participants, and accept invitations in WITT. Participants are expected to make bidirectional edits with full read/write access. Current validation and release work belongs in [todo.md](todo.md).

## Native Experience

WITT should feel fast, calm, and practical during physical cataloguing sessions. Use standard SwiftUI navigation, tabs, split views, lists, forms, search, sheets, toolbars, camera surfaces, and system controls. Let iOS 26 provide its native appearance, including Liquid Glass where the system applies it.

Do not add custom glass backgrounds, blur materials, translucent capsules, decorative borders, or custom glass button treatments by default. Keep the content layer clear and readable; express hierarchy through layout, grouping, typography, imagery, and restrained system tint. Avoid heavy onboarding and marketing surfaces. WITT opens on Browse, with Scan kept one tap away.

The iPhone experience prioritizes quick, linear movement through capture and detail. The iPad experience uses available space for sidebar-based browsing while preserving the same catalogue model and actions.

## MVP Non-Goals

- QR codes for Rooms or Things.
- Barcode-based stock control, quantities, pricing, procurement, or warehouse workflows.
- Public catalogues or sharing below the Place level.
- Fully automatic AI saves without user review.
- A custom visual design system that replaces standard iOS controls.
- Shipping a long-lived AI provider credential in the app.
- Maintaining speculative features, unresolved questions, or release tasks in this document; track them in [todo.md](todo.md).
