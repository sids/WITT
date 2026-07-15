# Place Sharing Spike

This is the execution record for `CLOUD-001`, `CLOUD-002`, and `CLOUD-003` in [todo.md](todo.md). The tracker remains the source of task status; this document holds the repeatable fixture, measurements, and evidence.

## Build Under Test

- App: WITT `1.0 (7)` from commit `d723e9e3bc3cd6bd1557d7ee4c2a7dfc813de07c`
- CloudKit container: `iCloud.in.sids.witt`
- Participants: Account A and Account B on separate physical devices
- Result: Not started

Do not record Apple IDs, invitation URLs, CloudKit tokens, or other credentials here.

## Production Schema Gate

Before interpreting any TestFlight sharing result:

1. Export or inspect the production schema for `iCloud.in.sids.witt`.
2. Confirm Core Data record types for `Area`, `Container`, `PhotoAsset`, `Place`, `QRCode`, `Room`, `Thing`, and `ThingKeyword`.
3. Confirm `PhotoAsset.data` and `PhotoAsset.thumbnailData` have their CloudKit asset mappings.
4. Confirm production logs contain no missing-field or unknown-record-type errors.

Record the verification time, schema result, and any deployment performed under Results.

## Fixture

Create private controls `C2-PRIVATE-A` and `C2-PRIVATE-B`, one per account. They must never appear on the other account.

On Account A, create `C2-SHARED-<UTC timestamp>` containing:

- Place: distinctive photo and details
- Rooms: `Garage-A` and `Study-A`
- Storage Areas: `Shelf-A` with photo and `Desk-A`
- Containers: `Blue-Bin-A` with photo and attached QR, containing `Pouch-A`
- Thing: `Red-Drill-A` inside `Pouch-A`, with a realistic camera photo, details, and keywords `cloud002-a` and `red`

Expected minimum shared graph: 1 Place, 2 Rooms, 2 Storage Areas, 2 Containers, 1 Thing, 2 keywords, 1 QR record, and 4 PhotoAssets.

## Run

Capture UTC timestamps for invitation open, acceptance alert, first visible Place, complete graph, all visible thumbnails, and cold-launch persistence.

1. Cold-launch Account A and confirm the fixture.
2. From the Place ellipsis menu, choose **Share Place**, invite Account B, then use **Shared** to confirm the participant is pending. Confirm Account B cannot yet see the Place.
3. Force-quit WITT on Account B, open the invitation, and expect **Place Added**. Select the shared Place from the Place menu if needed.
4. On Account B, verify every name, detail, keyword, relationship, and visible image. Scan `Blue-Bin-A`'s QR and confirm the known-code add flow opens at that Container; cancel without saving.
5. On Account B, add `B-Thing` to `Blue-Bin-A` with keyword `cloud002-b` and a new camera photo. Verify the Thing and image arrive on Account A and survive a cold launch.
6. On Account B, rename `Red-Drill-A`, change its keywords, move it to `Desk-A`, and replace its photo. Verify all four changes on Account A. Repeat the four edit classes from A on `B-Thing` and verify on B.
7. Take Account B offline, cold-launch, and confirm the cached graph and images render. Make a distinctive offline edit, confirm A does not receive it yet, reconnect B, and time convergence.
8. Reinstall build 7 on Account B while the share remains accepted. Time first Place, complete graph, thumbnails, and original-photo asset hydration. Record whether a new private `Home` Place appears.
9. On Account A, revoke Account B. Confirm the shared Place becomes unavailable on B while `C2-PRIVATE-B` remains. Confirm the old invitation can no longer restore access.
10. Reinvite Account B while WITT is already foregrounded to exercise foreground invitation acceptance.
11. Inspect production CloudKit records/logs. Confirm the shared zone contains the complete graph and both photo payload fields, B-created descendants use the shared zone, private controls remain isolated, and no recurring transfer errors appear.

Visible images are not sufficient evidence for original-photo transfer because WITT normally renders thumbnails. Original and thumbnail asset presence and size must also be verified in CloudKit or with a diagnostic build.

## Pass Criteria

- `CLOUD-001`: the complete build-7 schema is present in production with no schema errors.
- `CLOUD-002`: both accounts converge on the complete graph; B-created content is shared back to A; bidirectional, offline, fresh-install, revocation, and both invitation paths work without data loss; private Places never cross accounts.
- `CLOUD-003`: original and thumbnail payloads survive A-to-B and B-to-A transfer, cold launches, fresh hydration, and offline recovery with acceptable latency and no recurring errors.

Any missing or corrupt graph/photo, wrong-store record, private-data leak, failed read/write edit, or sync that remains stuck on stable connectivity is a failure. Thumbnail-only evidence leaves `CLOUD-003` inconclusive.

## Results

- Production schema verified at:
- Schema deployment performed:
- Account A device / OS:
- Account B device / OS:
- Invitation accepted at:
- Complete graph visible after:
- All thumbnails visible after:
- Original assets verified after:
- B-to-A new Thing latency:
- A-to-B edit latency:
- Offline reconnect latency:
- Fresh-install hydration latency:
- Revocation result:
- CloudKit errors:
- Final result:
- Follow-up defects:
