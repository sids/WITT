# WITT Product Decision Recommendations

Prepared July 15, 2026 for Sid's review. This brief recommends product direction for `SEARCH-001`, `AI-002`, `THING-001`, and `PLACE-001`, and records the provisional position for `SHARE-001` before the two-account sharing spike. These recommendations are not locked decisions until Sid accepts them; implementation and task status remain in `todo.md`.

The recommendations preserve WITT's core promise: help someone answer where a Thing is, quickly and confidently, while cataloguing real belongings in messy Places. They do not expand WITT into stock control or generic inventory management.

## Decision Summary

| Decision | Recommendation | Version 1 position |
| --- | --- | --- |
| `SEARCH-001` duplicate detection | Do not add automatic duplicate detection | Deferred; Find remains the way to recognize an existing Thing |
| `AI-002` confidence visibility | Do not show an AI confidence score | Keep confidence internal for evaluation and, only after calibration, review behavior |
| `THING-001` quantity | Do not add quantity | One Thing record represents one findable item or user-named group |
| `PLACE-001` direct-to-Room placement | Support it as a fallback, not the normal capture path | Keep Room as a valid location without promoting a Room-level New Thing tile |
| `SHARE-001` shared-edit conflicts | Ship simple system convergence if the spike proves it trustworthy | No custom conflict UI unless concurrent-use evidence shows a material problem |

## SEARCH-001: Duplicate-Thing Detection

### Recommendation

Do not implement automatic duplicate detection in version 1. WITT should help the user recognize an existing Thing through Find, but it should not interrupt capture with a speculative duplicate warning.

### Rationale

- Similar names are normal in a home: batteries, extension cords, seasonal decorations, and duplicate tools may be distinct Things in different locations.
- Name similarity alone is weak evidence. Photos, keywords, and location can distinguish Things, but reliable multimodal matching would add latency and uncertainty to the fast cataloguing loop.
- A false warning costs attention on every repeated capture. An occasional duplicate record can already be found, inspected, edited, moved, or archived through the existing catalogue.
- The current Find loop searches names, keywords, and location paths across Places. That is the right version 1 recovery path and also the right place to learn whether duplicates are a real user problem.

### Version 1 Scope

- Keep capture and Save free of duplicate checks, warnings, merge choices, and blocking confirmation.
- Keep Find results photo-led and location-aware so similarly named Things can be distinguished.
- Do not add duplicate state, similarity scores, merge semantics, or a new repository operation.
- Treat two records with the same normalized name as valid catalogue data.

### Acceptance Criteria

- Adding a Thing never pauses for or displays a possible-duplicate warning.
- Things with identical names can be saved in the same or different locations.
- Find can return all matching Things and each result communicates its current location.
- A user who recognizes an accidental duplicate can open it and use existing edit/archive behavior; no data is silently merged or removed.

### Defer And Measure

During `QA-001` and TestFlight review, record duplicate-related incidents separately as:

- accidental repeat capture because the user forgot a Thing was already catalogued;
- intentional same-name Things incorrectly perceived as duplicates;
- time spent using Find before capture;
- cleanup needed after a physical cataloguing session.

Promote duplicate assistance only if repeated real sessions show accidental duplicates are common enough to damage trust or create meaningful cleanup work. A reasonable trigger is accidental duplication in at least 10% of observed multi-Thing sessions or the same problem independently reported by at least three households. Start with an optional pre-capture Find affordance or a nonblocking post-save suggestion. Do not pursue automatic merging without evidence that photo-and-location matching is precise and that users understand which record survives.

## AI-002: Confidence Visibility

### Recommendation

Do not show numeric, percentage, meter, or high/medium/low AI confidence to users in version 1. Retain confidence in the provider-neutral suggestion contract for evaluation. Use it to change review behavior only after the production model is calibrated against WITT's household-item evaluation set.

### Rationale

- Provider confidence is not yet calibrated for WITT's photos, names, or household vocabulary. A precise-looking number would imply reliability that has not been established.
- Every AI result is already a suggestion: fields remain editable, Save follows normal form validity, and the user reviews the record before saving.
- Confidence in the proposed name does not necessarily describe confidence in keywords, distinguishing details, or whether the photo contains one Thing.
- Honest states such as analyzing, suggestion ready, unavailable, and manual entry are more actionable than an unexplained score.

### Version 1 Scope

- Keep confidence in the transient `ThingLabelSuggestion` contract and production-model evaluation data.
- Do not persist confidence on a Thing or show it in Review Thing, Add Thing, Thing detail, or Find.
- Do not disable Save or erase a usable suggestion solely because confidence is low or absent.
- If `AI-001` evaluation establishes a useful threshold before release, low confidence may internally leave uncertain fields blank or keep review emphasis on them. The user-facing copy must describe the action needed, not expose the score.

### Acceptance Criteria

- No user-facing AI confidence number, band, badge, color scale, or certainty claim appears.
- AI-filled fields are visibly ordinary editable fields and require the same review-and-Save step as every suggestion.
- Missing or low confidence does not prevent manual entry or a valid Save.
- The selected production model is evaluated by confidence band for naming correctness, misleading suggestions, and blank-field behavior before confidence affects the flow.
- Any internal threshold is model-specific, documented with evaluation results, and can be changed without migrating catalogue data.

### Defer And Measure

In the `AI-001` evaluation set, measure name correctness and harmful suggestion rate by confidence band, calibration error, user correction rate, and whether a low-confidence flag predicts corrections better than simple failure/empty-output signals. Consider user-visible confidence only if all of the following become true:

- the score is calibrated and stable for the production model;
- users make a materially better review decision when shown it;
- the display does not cause automation bias or needless rechecking;
- the meaning can be explained without adding friction to repeated capture.

Otherwise confidence remains internal. A model or provider change requires recalibration before its score drives behavior.

## THING-001: Quantity

### Recommendation

Do not add quantity to version 1. A Thing is a findable catalogue record with one current location, not a stock-keeping unit.

### Rationale

- Quantity introduces stock-control expectations: increments, decrements, units, partial moves, depletion, and reconciliation. Those are outside WITT's promise.
- Several similar objects may be individually worth finding because they live in different places. One quantity value would hide that location truth.
- When a group is usefully found together, the user can name the group as the Thing they expect to search for, such as "box of spare bulbs."
- The current model's one Thing to one Room, Storage Area, or Container relationship stays clear and dependable.

### Version 1 Scope

- Do not add a quantity field, unit, stepper, badge, aggregate count, or quantity-aware search.
- Keep Browse counts as counts of active Thing records, including descendants; do not reinterpret them as summed quantities.
- Permit user language that describes a grouped Thing without parsing it into stock data.
- Do not add partial-move or split-record behavior.

### Acceptance Criteria

- Thing capture, edit, detail, Find, and Browse contain no quantity control or derived quantity total.
- Each Thing still has exactly one current location.
- Moving a Thing moves the entire record; WITT never asks how many units moved.
- A grouped Thing can be named naturally and found like any other Thing.

### Defer And Measure

During physical-session QA, record requests to know "how many" separately from requests to know "where." Note whether the objects are interchangeable, stored together, and expected to move as a group. Reconsider only if multiple households repeatedly need counts to complete the find loop, not merely because quantity is conventional in inventory software. Any promoted design must first define units, grouped versus individual Things, partial moves, and how counts behave across locations. Until those semantics are product-tested, quantity stays deferred.

## PLACE-001: Direct-To-Room Thing Placement

### Recommendation

Treat direct-to-Room placement as a supported fallback when a Thing genuinely belongs to the Room as a whole. Storage Areas and Containers remain the normal, more precise cataloguing destinations.

### Rationale

- Real homes contain Things that do not fit a useful Storage Area or Container: a floor lamp, exercise bike, freestanding fan, or wall-mounted item.
- Forcing a synthetic Storage Area would make the recorded answer less natural and add setup friction.
- Promoting Room placement equally with Storage Area and Container placement would encourage vague locations and weaken WITT's ability to answer where a Thing is.
- The current domain already supports a Room as exactly one current Thing location, displays direct Things on the Room screen, includes Rooms in the Location picker, and preserves them through Browse and Find. The Room screen correctly emphasizes New Storage Area rather than a direct New Thing tile.

### Version 1 Scope

- Keep Room as a valid Thing destination in persistence, movement, Browse restoration, Find, and location selection.
- Keep direct Room Things visible in their Room's Things collection and included in descendant counts.
- Do not add a Room-level New Thing tile or make Room the QR-first destination; Rooms do not receive QR codes.
- A user creating or editing a Thing through the management form may choose the Room when no more precise destination applies.
- Known-QR capture continues to save to the scanned Storage Area or Container without prompting for a broader location.

### Acceptance Criteria

- A Thing can be saved or moved directly to an active Room within its Place.
- A direct Room Thing appears on the Room screen, in Find, and at the correct Room path when opened.
- Its displayed location is the Place and Room, with no invented Storage Area or Container.
- Contextual New Thing from a Storage Area or Container remains preselected to that exact destination.
- The Room screen's primary creation emphasis remains New Storage Area; direct Room placement is available through Location selection without competing with the QR-first loop.
- Archiving the Room includes its direct Things in the existing impact confirmation and archive behavior.

### Defer And Measure

In `QA-001`, record how often users choose Room after beginning contextual Thing capture, what kinds of Things they place there, and whether they later move them to a more precise destination. Promote a secondary Room-level Add Thing action only if users repeatedly need direct placement and the current Location-picker path is hard to discover. If direct Room placement becomes a default shortcut or produces vague failed finds, keep it available only during edit/move and improve guidance toward Storage Areas rather than removing the valid domain relationship.

## SHARE-001: Shared-Edit Conflict Position Before The Spike

### Recommendation

Use simple CloudKit/Core Data convergence with no custom conflict surface as the version 1 baseline, conditional on the two-account sharing spike proving that both devices converge promptly to one coherent Place graph. Do not design a merge center, edit locks, activity feed, or version history before real shared-Place evidence exists.

This is a provisional product position, not a claim that current merge behavior is sufficient. The spike must verify it.

### Rationale

- WITT sharing is for a household or small trusted group, where simultaneous edits to the same Thing should be uncommon compared with capture, movement, and sequential cleanup.
- A generic conflict UI would add substantial complexity without yet knowing which conflicts occur or whether users can resolve them meaningfully.
- The implementation already imports persistent history and merges remote changes, but its local object-trump merge policy is an engineering mechanism, not a user-facing conflict guarantee.
- Some invariants are more important than preserving every competing field value: one current Thing location, valid containment, one active target per QR payload, correct shared-store assignment, and an intact photo relationship.

### Version 1 Scope

- Show the converged catalogue state without a custom conflict badge or chooser when the spike passes.
- Continue to rely on normal editable detail screens for correcting an unexpected final value.
- Keep `updatedAt` as catalogue metadata; do not present it as proof of authorship or a complete edit history.
- Do not add collaborator attribution, field-level versions, locks, undo across devices, or location history.
- Extend spike evidence to cover same-record concurrency, not only sequential bidirectional edits.

### Acceptance Criteria

Before accepting simple convergence for version 1, the sharing spike must demonstrate on two physical devices and two iCloud accounts:

- simultaneous different-field edits to one Thing converge on both devices without losing unrelated valid data;
- simultaneous edits to the same text field converge to one coherent value on both devices, with no oscillation or permanent divergence;
- competing Thing moves leave exactly one valid current location and the same location on both devices;
- edit-versus-archive leaves a coherent active or archived result with no orphaned descendants;
- photo replacement versus text edit leaves a renderable photo relationship and coherent text;
- concurrent creation and QR operations preserve containment and QR uniqueness invariants;
- offline edits made on both devices converge after reconnect within an observed, recorded latency;
- cold launch after convergence shows the same graph on both devices.

Any crash, invalid hierarchy, multiply active healthy QR binding, lost photo relationship, private/shared store leak, permanent divergence, or silent loss of unrelated fields fails this position and blocks release until addressed. A same-field winner that surprises one tester is recorded as a usability observation; it does not by itself require a conflict UI if both devices converge and correction is straightforward.

### Defer And Measure

During the spike and TestFlight shared-Place use, record conflict scenarios, time to converge, whether users notice an overwritten value, whether they can correct it, and whether the final graph violates a WITT invariant. Keep advanced conflict handling deferred if collisions are rare, convergence is dependable, and correction is easy.

Promote targeted handling when evidence shows one of these conditions:

- repeated silent loss of edits across normal household use;
- conflicts that produce an invalid or ambiguous current location;
- photo or QR relationship corruption;
- prolonged divergence on stable connectivity;
- users cannot tell which value is current or safely repair it.

Respond to the observed conflict class rather than building a generic merge system. Invariant-threatening operations may need repository-level reconciliation or an explicit retry; frequently overwritten descriptive fields may need lightweight "changed elsewhere" messaging. Full conflict history remains deferred unless simpler handling fails.

## QR-003 Reference

`QR-003` is complete. Runtime writes and reads of `QRCode.lastScannedAt` are retired because version 1 has no scan-history behavior. The optional deployed Core Data attribute remains only for additive CloudKit/store compatibility, and legacy values are preserved without influencing the product. None of the recommendations above depend on scan-recency metadata.
