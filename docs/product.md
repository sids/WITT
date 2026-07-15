# WITT Product

WITT means "Where Is That Thing?" It is a native iOS app for people who need to catalogue belongings across a home or another real-world place and later answer, quickly and confidently, where an item is. It is designed for individuals, households, and trusted collaborators working in messy storage environments with nested containers, similar-looking things, and locations that change over time.

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
- Any non-empty QR-code payload can attach to a Storage Area or Container. WITT-generated labels use versioned `witt://` links so scanning them outside the app can launch WITT directly. Rooms and Things do not receive QR codes in the MVP.
- The current attach flow offers targets without an active QR. Whether WITT should support multiple active QR codes per target remains a product decision in [todo.md](todo.md).
- New Storage Areas and Containers may scan and bind any unused QR code before saving. Existing targets expose Attach QR Code or Reattach QR Code from their navigation action menu. Reattaching replaces that target's current binding and makes its former label unassigned again; WITT must reject, rather than silently move, a scanned code already attached elsewhere.
- Things always have one current location and can be moved within the same Place.
- Containers may be nested. Archiving a parent archives its contained catalogue branch after confirmation.
- Sharing is rooted at the Place and grants invited participants complete read/write collaboration for that Place.
- AI assists with photo understanding, but the user remains responsible for reviewing the saved record.
- The app supports iPhone and iPad and requires iOS 26.

## QR-First Cataloguing

The trailing Scan QR control is a first-class entry point for repeated cataloguing while moving around a home. The in-app scanner accepts any QR code with a non-empty payload. WITT also handles its own versioned `witt://` links when another scanner or camera app opens them directly.

### Known QR

Scanning a code already attached to a Storage Area or Container opens Add Thing for that destination. WITT offers the camera immediately, also permits choosing a photo, then analyzes the image and opens Review Thing. Name, comma-separated keywords, and notes remain editable while analysis runs, and the user may save as soon as the normal form requirements are met. A late suggestion fills only fields the user has not touched. If AI is unavailable, the same form remains usable with honest error messaging, retry, and manual entry.

### Unknown QR

Scanning an unassigned code opens Attach QR directly. WITT first lists Storage Areas and Containers that do not already have a QR, grouped by type and labeled with their location paths. The user can attach in one step.

When no suitable target exists, or the user chooses Create & Attach, one screen supports selecting or creating the Place context, Room, and Storage Area, then attaching to that Storage Area or selecting or creating a Container. Creation and attachment succeed as one operation. There is no intermediate QR explanation screen and no option to bind the code to a Room or Thing.

## Browse And Creation

Browse opens by default on the selected Place's Rooms screen; there is no Places screen. Its title is the Place name. A standard ellipsis menu beside the title contains Rename Place and Share Place, followed by a divider and Print QR Labels. When the Place already has an active iCloud share, a separate Shared button appears immediately before the ellipsis and opens the system sharing details and participant actions.

The system bottom toolbar follows the compact Mail pattern: a leading menu for switching or creating Places, system search in the center, and a trailing Scan QR button. The Place menu clearly marks the current Place and stays focused on Place selection and creation. Switching Places returns to that Place's Rooms screen. With no active Place, New Place is the primary path forward.

Browse follows the same hierarchy on iPhone and iPad: selected Place, Room, Storage Area or Container, then Thing. WITT remembers both the selected Place and deepest in-Place destination across launches, restoring the current hierarchy when content has moved. A missing or archived destination returns to the selected Place's Rooms screen; an unavailable selected Place falls back safely to another active Place. A Room selected explicitly from the Place root always replaces any previously restored path and opens that exact Room.

Creation is contextual:

- A Place offers New Room.
- A Room offers New Storage Area and displays Things and Containers located directly in the Room.
- A Storage Area offers New Container or New Thing.
- A Container offers New Container or New Thing, including nested Containers.
- New Storage Area and Container forms can optionally scan an unused QR label. Their detail screens keep QR assignment in the ellipsis menu rather than showing QR status in the content layer.
- Management forms support create, edit, same-Place move, photo replacement or removal, and archive with impact confirmation. Add Thing never blocks manual entry or a valid Save on AI analysis; late or stale analysis results cannot overwrite user edits.

Storage Area details appear as secondary, noninteractive text immediately beneath the screen title rather than inside a grouped row that resembles a button. A native segmented control below the details switches between Things and Containers, defaults to Things, and shows the matching collection and contextual New tile.

Browse collections should make each hierarchy level recognizable at a glance:

- Rooms use two-column landscape tiles with a left icon, a two-line name, and the total number of descendant Things.
- New Room is a matching dashed tile inside the Room grid; when it is the only tile, it remains one column wide and centered.
- Storage Areas use native list rows with a larger name, smaller descendant Thing count, and photo or cabinet fallback on the right. When no Storage Areas exist, New Storage Area is a standalone full-size row with a fully dashed rounded outline. When the list is populated, it becomes the attached transparent final row: a native separator beneath the preceding Storage Area, no dashed top edge, tint-matched sides aligned to the full width of the native rows above, and intact rounded bottom corners joining a dashed bottom edge.
- Things use low-margin two-column square photo tiles with the name in a restrained translucent bottom overlay. New Thing is a matching dashed tile in the grid.
- Containers use low-margin two-column square photo tiles with centered name and descendant Thing count in a restrained translucent overlay. New Container is a matching dashed tile in the grid.

Every dashed creation outline uses the same system tint as the icon and text inside it.

Counts include active Things nested anywhere beneath the displayed Room, Storage Area, or Container. Missing photos use clear system-image fallbacks. These layouts belong to Browse; Find remains optimized for scanning search results.

## Find Loop

Find is the system search control in the center of the bottom toolbar, not a separate tab. Activating it searches all active Things across every Place by Thing name, keywords, and every component of the location path. A result shows the Thing and its location; opening it navigates through the result's current Place hierarchy to its detail, switching the selected Place when necessary. Canceling search without choosing a result leaves the Browse position unchanged. The core loop is simple: search for what you remember, recognize the Thing, and read where it is.

The trailing Scan QR button presents the live camera full-screen over Browse. A standard close button dismisses it and returns to the exact prior Browse position. A recognized code continues directly into the known- or unknown-QR flow after the camera closes.

## Printable QR Labels

WITT generates 1 to 120 random, unassigned QR codes as a printable PDF. Generating a sheet does not persist or reserve those tokens; a code becomes part of the catalogue only when it is scanned and attached.

- **Paper:** Choose A4, US Letter, or Custom. A4 and US Letter supply their standard width and height automatically. Custom takes a metric width and either a fixed height or unlimited continuous-roll length.
- **Physical layout:** Set left, right, top, and bottom paper margins; exact label width and height; and horizontal and vertical gaps. WITT derives the labels per row, labels per fixed page, and continuous output length from those measurements.
- **Default stock:** Custom opens at 100 mm wide with unlimited length, 25 × 25 mm labels, and zero margins or gaps. This matches the linked True-Ally four-up 25 mm square roll.
- **Label content:** A square label contains only its QR code. A rectangular label places its short Code ID beside the QR and can optionally add a write-in line below the ID.
- **Output:** Codes are crisp, high contrast, and validated to keep at least a 20 mm QR frame. The app previews the dimensionally accurate PDF with Quick Look, then uses the native share and print flow.

## Sharing

A Place is the complete collaboration boundary. Its Rooms, Storage Areas, Containers, Things, QR associations, and photos are expected to travel together through iCloud sharing. Owners can create or manage a Place share, invite participants, and accept invitations in WITT. Participants are expected to make bidirectional edits with full read/write access. Current validation and release work belongs in [todo.md](todo.md).

## Native Experience

WITT should feel fast, calm, and practical during physical cataloguing sessions. Use standard SwiftUI navigation, lists, forms, search, sheets, toolbars, camera surfaces, and system controls. Let iOS 26 provide its native appearance, including Liquid Glass where the system applies it.

Do not add custom glass backgrounds, blur materials, translucent capsules, decorative borders, or custom glass button treatments by default. Keep the content layer clear and readable; express hierarchy through layout, grouping, typography, imagery, and restrained system tint. Avoid heavy onboarding and marketing surfaces. WITT opens on Browse, with Scan kept one tap away.

The iPhone experience prioritizes quick, linear movement through capture and detail. The iPad experience uses available space while preserving the same selected-Place hierarchy, catalogue model, and actions.

## MVP Non-Goals

- QR codes for Rooms or Things.
- Barcode-based stock control, quantities, pricing, procurement, or warehouse workflows.
- Public catalogues or sharing below the Place level.
- Fully automatic AI saves without user review.
- A custom visual design system that replaces standard iOS controls.
- Shipping a long-lived AI provider credential in the app.
- Maintaining speculative features, unresolved questions, or release tasks in this document; track them in [todo.md](todo.md).
