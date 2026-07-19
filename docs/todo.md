# WITT Todo

Updated July 19, 2026.

This is the canonical source of truth for actionable WITT work. New TestFlight feedback lands in the inbox before implementation starts. Completed work belongs in [status.md](status.md), [release.md](release.md), and Git history rather than accumulating here.

Priority meanings:

- P0: release gate or blocks trustworthy testing.
- P1: next product or engineering work.
- P2: deliberately deferred; not committed scope until promoted.

Workflow:

1. Add each new observation with a stable ID, source/date, and affected build.
2. Preserve Sid's wording where useful, then add acceptance criteria during triage.
3. Move triaged work into the appropriate priority section; do not silently delete open work.
4. Mark work complete only after verification, then remove it once its durable outcome is recorded elsewhere.
5. For every UI change, share simulator screenshots in the project-manager thread before calling the work complete. Cover each materially changed screen, relevant populated and empty states, and both iPhone and iPad when responsive behavior differs.

## Feedback Inbox

- [ ] FB-001 - Continue collecting and triaging Sid's feedback on the current TestFlight build; latest is `1.0 (7)`. Close when Sid considers the review pass complete.
- [ ] TF-003 - Add Divya to `WITT Internal` for the two-account sharing spike. Sid grants her WITT app visibility in App Store Connect while retaining her current apps and SALES role; Codex then sends and verifies the TestFlight group invitation.
- [ ] FB-030 - Rename the App Store-facing app from `WITT: Where Is The Thing?` to match the new expansion, `WITT: Where Is That Thing?`. Apple rejected the exact requested name because another account uses it. Choose an available variant, update the `en-US` App Info localization, and verify the App Store Connect record while keeping the on-device label `WITT`.

## P0 - Release Gates

- [ ] CLOUD-002 - Run the real-device, two-iCloud-account Place-sharing spike using [sharing-spike.md](sharing-spike.md).
  - [ ] Use two physical devices signed into different iCloud accounts.
  - [ ] Account A creates and shares a Place containing every hierarchy level, keywords, a QR binding, and realistic Place and Thing photos; Account B accepts it.
  - [ ] Verify complete graph and `PhotoAsset` hydration after cold launch, then bidirectional creation, edits, movement, photos, and archive propagation.
  - [ ] Exercise pending acceptance, revocation, offline/reconnect, fresh-install hydration, persistent-store assignment, isolation, conflicts, and recoverable failures.
  - [ ] Record initial-share/photo latency and inspect CloudKit Dashboard or logs for record shape, assets, errors, and transfer size.
- [ ] CLOUD-003 - Decide the production photo design from the sharing-spike evidence.
  - [ ] Keep Core Data external Binary Data if transfer and performance are dependable.
  - [ ] If transfer is unreliable, design a hybrid `PhotoAsset` metadata, local-file, and shared CloudKit asset migration.
  - [ ] If reliable but slow, tune original/thumbnail dimensions and storage policy.
- [ ] AI-001 - Activate production AI without putting a long-lived provider key in the app.
  - [x] Defined the provider-neutral relay, App Attest/short-lived credential boundary, privacy controls, limits, monitoring, evaluation gates, rollout, and rollback plan in [ai-production.md](ai-production.md).
  - [ ] Choose and operate the WITT-owned relay and mobile-auth strategy.
  - [ ] Choose the production provider, pinned model, endpoint policy, and contractual retention/training terms.
  - [ ] Approve user disclosure, consent, App Store privacy answers, operational metadata retention, and support ownership.
  - [ ] Configure spend/rate limits, monitoring, failure visibility, and a remote kill switch.
  - [ ] Build a consented representative photo corpus and evaluation harness outside the shipping app target.
  - [ ] Implement and wire the app relay adapter only after the real contract is fixed and accepted evaluation gates pass.
- [ ] QA-001 - Complete physical-device cataloging and accessibility QA on iPhone and iPad.
  - [x] Simulator audit covered standard and Accessibility XXXL sizes with increased contrast; grids adapt to one column, Review Thing photos have explicit labels, and QR numeric fields remain readable.
  - [ ] Exercise first launch, Browse, Search, QR flows, management, photos, printing, deep links, and Place sharing.
  - [ ] Catalogue at least 10 real Things while moving around a home and record interaction friction.
  - [ ] Verify camera and Photos permissions, interruption, offline/sync-pending behavior, VoiceOver order, contrast, hit targets, hardware keyboard, rotation, and iPad split view.
  - [ ] Repeat photo ingestion long enough to expose memory growth or thermal issues.

## P1 - Product Decisions

- [ ] SEARCH-001 - Accept or revise the recommendation to defer automatic duplicate-Thing detection and measure accidental duplicates during real cataloging.
- [ ] AI-002 - Accept or revise the recommendation to keep uncalibrated AI confidence internal in version 1.
- [ ] THING-001 - Accept or revise the recommendation to omit stock-style quantity from version 1.
- [ ] PLACE-001 - Accept or revise direct-to-Room Thing placement as a supported fallback without promoting a Room-level New Thing action.
- [ ] SHARE-001 - After the sharing spike, confirm whether simple last-writer convergence is acceptable or needs targeted user-facing conflict handling.

The prepared recommendations and failure criteria are in [product-decisions.md](product-decisions.md).

## P1 - Engineering And Operations

- [ ] CLOUD-004 - Add restrained CloudKit sync diagnostics after the sharing spike identifies useful failure signals.
- [ ] PHOTO-001 - Complete physical-device photo-ingestion profiling.
  - [x] Simulator profiling rejected two higher-memory alternatives; photo-library work is lifecycle-bound, prevents overlapping selection, cooperates with cancellation, and suppresses stale callbacks.
  - [ ] Repeat full-resolution camera and iCloud-library ingestion on devices, including dismiss/reopen, memory warnings, sustained sessions, and thermal pressure.
- [ ] TEST-001 - Add focused regression tests with each change and keep both full simulator configurations green.
  - [x] July 19 simplification checkpoint: 171 Debug and 167 Release-optimized tests passed with zero failures or skips; Debug and Release builds succeeded, and Release inspection found no screenshot-demo, mock-labeling, relay, or evaluator symbols.

## P2 - App Store Release

- [ ] RELEASE-001 - Replace the provisional app icon with an approved production icon.
  - [x] Prepared three directions in [app-icon-concepts.md](app-icon-concepts.md); Direction B is recommended.
  - [ ] Sid selects a direction or requests another concept round.
  - [ ] Redraw the selected mark as editable layers, tune variants in Icon Composer, and verify real-size rendering before replacing `AppIcon`.
- [ ] RELEASE-002 - Complete App Store packaging using [app-store.md](app-store.md).
  - [x] Drafted listing copy, review notes, screenshot story, fixture guidance, and code-grounded privacy mapping.
  - [x] Added and exercised a non-destructive screenshot pipeline that preserves Simulator data and CloudKit entitlements.
  - [ ] Choose an available App Store name and replace the listing placeholder.
  - [ ] Publish and approve public support and privacy-policy destinations, including final AI disclosure if AI ships.
  - [ ] Build the fictional catalogue fixture and capture, curate, and inspect final iPhone and iPad screenshot sets.
  - [ ] Reconcile the archived binary and production services with App Privacy and age-rating questionnaires, then enter approved metadata in App Store Connect.
- [ ] RELEASE-003 - Archive with an Apple-accepted stable Xcode before App Store submission if the beta toolchain is no longer accepted.
- [ ] RELEASE-004 - Complete final device, CloudKit, AI, privacy, accessibility, and data-loss checks before submitting version 1.0.

## P2 - Parking Lot

Do not schedule these until Sid explicitly promotes them:

- [ ] LATER-001 - Multi-photo capture for a Thing.
- [ ] LATER-002 - Thing location history or move events.
- [ ] LATER-003 - Persisted printable-QR batches, provenance, and reprint history.
- [ ] LATER-004 - Durable provider-neutral AI attempt history or an explicit audit/debug mode.
- [ ] LATER-005 - Advanced shared-edit conflict UI beyond simple last-writer behavior.
- [ ] LATER-006 - Richer Container/Storage Area metadata such as kind, capacity, wall, shelf, or label hints.
