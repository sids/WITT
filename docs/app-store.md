# WITT App Store Packaging

This is the first-draft App Store packaging source for WITT 1.0. It is grounded in the implemented repository as of July 15, 2026. It does not submit metadata, create accounts, or resolve product, provider, legal, or URL decisions that are not represented in the repository.

## Recommended Listing

### Name

The exact name `WITT: Where Is That Thing?` is unavailable. Recommended alternatives, all within Apple's 30-character app-name limit, are:

1. **WITT: Find Your Things** - recommended; clear, natural, and faithful to the product.
2. **WITT: Where Things Are** - closest to the expanded brand without copying the unavailable name.
3. **WITT: Home Item Finder** - strongest search intent, but more generic.
4. **WITT: Find It at Home** - compact and approachable.
5. **WITT: Where Is The Thing?** - the current App Store Connect record; grammatical phrasing is less natural.

Availability must be checked in App Store Connect before choosing. Placeholder requiring Sid's decision: `<FINAL_APP_NAME>`.

### Subtitle

**Catalog, scan, find at home**

This is within the 30-character limit and describes the core loop without claiming unavailable AI behavior.

### Promotional Text

**Give every box, shelf, and drawer a place in your home catalog. Scan a QR label to add what is there, then search WITT whenever you need to find it.**

This is within the 170-character limit and may be updated without a new app version.

### Full Description

WITT helps you remember where things are kept around your home.

Create a catalog that matches the way your space actually works: Places contain Rooms, Rooms contain Storage Areas, and Containers can sit inside other Containers. Add photos, names, keywords, and notes to the Things you want to find later.

Use QR codes to make cataloging fast while you move around. Attach a label to a Storage Area or Container, scan it in WITT, take or choose a photo, review the details, and save. When you scan the same label again, WITT opens the right location so you can keep adding Things.

When you need something, search across your catalog by name, keyword, or location. WITT shows the Thing together with the path to where it lives.

With WITT you can:

- Organize belongings by Place, Room, Storage Area, and nested Container
- Photograph Things and the places where they are stored
- Attach existing QR codes or print your own label sheets
- Add multiple Things quickly during a cataloging session
- Search the full catalog and see each Thing's location
- Move records when storage changes
- Share an entire Place with trusted iCloud participants for read-and-write collaboration
- Use the same native catalog on iPhone and iPad

WITT is designed for real homes: crowded closets, stacked boxes, similar-looking items, and storage that changes over time.

iCloud availability is required for cloud sync and Place sharing. Camera access is optional but required to scan QR codes or take photos; photos may also be chosen from the photo library.

AI sentence to include only if live production labeling is enabled and the privacy policy, provider, and review behavior are approved:

`<OPTIONAL_AI_COPY: WITT can suggest a name and keywords from a Thing photo; you review and edit every suggestion before saving.>`

### Keywords

Proposed keyword field, within the 100-byte limit:

`home inventory,storage,organizer,find items,QR code,boxes,household,declutter,catalog`

Do not duplicate the final app name or subtitle unnecessarily. Recheck byte count after localization or title changes.

## Classification

- **Primary category:** Lifestyle
- **Secondary category:** Productivity
- **Age rating recommendation:** Complete the current App Store Connect questionnaire aiming for the lowest rating its answers produce (historically 4+). The repository contains no violence, sexual content, profanity, gambling, unrestricted web access, advertising, or public social network.
- **User-generated content:** WITT stores user-entered names, notes, keywords, and photos and can share them with specifically invited iCloud participants. Answer the questionnaire according to Apple's current definition even though there is no public feed or discovery.
- **AI-generated content:** If live photo labeling is enabled, disclose that suggestions may be generated from user photos and are always reviewed before save. Confirm whether the current questionnaire has a dedicated generative-AI item. If live labeling remains disabled in Release, do not claim the feature in the listing.

Final age-rating answers must be reviewed in the live questionnaire because its wording is not stored in this repository.

## App Review Notes

Suggested notes for the review submission:

> WITT is a native home-cataloging app. It does not have an app-specific login or demo account. The app creates a local/private iCloud-backed Place named Home on first launch.
>
> Core workflow: open a Room, create a Storage Area or Container, and add a Thing with a name and optional photo. Search is available from the bottom system toolbar.
>
> QR workflow: use Print QR Labels from the Place ellipsis menu, preview or print a generated label, then use Scan QR in the bottom toolbar. An unassigned QR can be attached to a Storage Area or Container. Scanning an attached QR opens Add Thing for that location. Any non-empty QR payload is accepted by the in-app scanner.
>
> Camera access is used only for QR scanning and Thing photos. The photo library can be used instead for Thing photos. Camera behavior should be reviewed on physical hardware because the Simulator does not provide a representative live camera.
>
> Place sharing uses Apple's iCloud sharing UI and requires iCloud availability. No credentials are supplied or required by WITT.
>
> `<AI_REVIEW_NOTE: State whether production photo labeling is disabled, or identify the approved user-visible behavior and relay/provider disclosure. Do not include API keys, tokens, private endpoints, or reviewer credentials.>`

Before submission, replace the AI placeholder and add any precise steps needed for the build selected in App Store Connect. Do not provide Sid's Apple ID, an iCloud test account, or provider credentials.

## Screenshot Story

Use real but non-private fixture content, consistent names, and the native light appearance unless a second appearance is intentionally submitted. Do not show personal addresses, faces, account names, notifications, or production household photos. Capture the same story on the required iPhone and iPad display classes.

Recommended sequence and overlay captions:

1. **Know where everything lives**
   Place Rooms screen with several recognizable rooms and useful descendant counts.
2. **Map storage the way your home works**
   A Room showing image-led Storage Areas plus direct Things or Containers.
3. **See inside every shelf and box**
   A populated Storage Area or Container with clear photo tiles and nested contents.
4. **Scan a label. Add what is there.**
   QR scanner or the known-QR Add Thing flow. Use the debug denied/restricted camera state only for QA evidence, not this marketing frame.
5. **Review the details before you save**
   Review Thing with a representative photo, name, and keywords. Mention suggestions only when live production labeling is enabled.
6. **Find a Thing and its full location**
   Search results showing a Thing and a readable path through its Place hierarchy.
7. **Print labels that fit your setup**
   QR label configuration or dimensionally accurate Quick Look preview.
8. **Share a Place with people you trust**
   WITT's sharing entry point without exposing participant names or Apple's account UI.

The first three frames should communicate the product without requiring text overlays to explain unfamiliar controls. Keep captions short and add them during final artwork production; the capture script records clean simulator pixels and does not composite marketing text or device frames.

Verify the required screenshot device classes and pixel dimensions in App Store Connect at upload time. The repository supports iPhone and iPad and requires iOS 26; it does not establish which screenshot slots Apple will require when the version is submitted.

## Screenshot Fixture

Prepare a dedicated Simulator and enter a small fictional catalog manually. Suggested fixture content is editorial guidance, not an app seed contract:

- Place: `Home`
- Rooms: `Garage`, `Kitchen`, `Study`, `Guest Room`
- Storage Areas: `Utility Shelves`, `Pantry`, `Desk Cabinet`, `Wardrobe`
- Containers: `Tool Box`, `Cables`, `Baking Supplies`, `Travel Adapters`
- Things: `Cordless Drill`, `HDMI Cable`, `Cake Tin`, `Passport Wallet`

Use licensed or purpose-made photos with no sensitive metadata or people. The app strips source metadata during normalization, but screenshot source assets still need an explicit right to use. Keep this dedicated Simulator's data between runs so captures remain stable. The capture script never erases a Simulator or uninstalls WITT.

## Capture Runbook

The script at `scripts/capture-app-store-screenshots.sh` uses `xcodebuild` and `xcrun simctl`. It requires a booted Simulator UDID rather than silently choosing or modifying a device. The build keeps Xcode's normal local Simulator signing so WITT's CloudKit entitlements remain available at launch.

```sh
# Show available devices and copy the UDID of a booted screenshot Simulator.
scripts/capture-app-store-screenshots.sh devices

export WITT_SIMULATOR_UDID='<BOOTED_SIMULATOR_UDID>'

# Build Debug into a temporary DerivedData directory and install it.
scripts/capture-app-store-screenshots.sh build
scripts/capture-app-store-screenshots.sh install

# Launch normally, stage the desired screen by hand, then capture it.
scripts/capture-app-store-screenshots.sh launch
scripts/capture-app-store-screenshots.sh capture '01-rooms'

# Launch a deterministic debug surface and capture after the default delay.
scripts/capture-app-store-screenshots.sh demo scanner-denied 'qa-scanner-denied'
scripts/capture-app-store-screenshots.sh demo review '05-review-thing'
```

`demo review`, `demo known`, and `demo repair` depend on suitable existing fixture destinations. Available deterministic presets are printed by the script's `demos` command. Debug launch arguments are compiled out of Release and are for screenshot staging and QA only.

Defaults can be overridden without editing the script:

```sh
WITT_OUTPUT_DIR='/absolute/output/directory' \
WITT_DERIVED_DATA='/absolute/derived-data/directory' \
WITT_CAPTURE_DELAY=3 \
scripts/capture-app-store-screenshots.sh demo attach 'attach-qr'
```

Every capture uses a new timestamped run directory and refuses to overwrite an existing PNG. The default output and DerivedData paths live under `${TMPDIR}` rather than the repository. The script does not reset content, alter privacy settings, create fixture records, add status-bar overrides, submit metadata, or contact App Store Connect.

For final captures:

1. Use a dedicated booted Simulator with the intended iPhone or iPad model and supported OS.
2. Build and install once, then preserve the fixture between launches.
3. Set the Simulator appearance, text size, language, locale, and orientation deliberately before each device-class run.
4. Close keyboards, menus, alerts, and notification overlays unless they are part of the intended frame.
5. Capture each screen and inspect the PNG at full resolution for clipping, private content, stale state, and inconsistent time or network indicators.
6. Record the source commit, Xcode version, Simulator model/runtime, appearance, locale, and output directory with the packaging handoff.

## Support And Privacy URLs

App Store Connect requires public HTTPS destinations controlled by WITT's publisher. These are release decisions and are not present in the repository:

- **Support URL:** `<PUBLIC_HTTPS_SUPPORT_URL>`
- **Privacy Policy URL:** `<PUBLIC_HTTPS_PRIVACY_POLICY_URL>`
- **Marketing URL:** `<OPTIONAL_PUBLIC_HTTPS_MARKETING_URL>`
- **Support contact:** `<PUBLIC_SUPPORT_EMAIL_OR_FORM>`

The support destination should identify WITT, provide a working contact path, state supported devices/OS, and cover camera permission recovery, iCloud availability/sharing, QR scanning/printing, data deletion, and current known limitations.

The privacy policy should identify the publisher and effective date; explain on-device processing, Core Data and iCloud/CloudKit storage, Place sharing, camera and photo-library access, photo metadata stripping, retention/deletion, and support contact handling; and describe the production AI relay/provider, purpose, transfer, retention, security, and user control if live labeling is enabled. It should not promise provider behavior that has not been selected and verified.

## App Privacy Questionnaire Mapping

This mapping describes repository behavior, not a final legal determination. Apple's definition of "collect" and the live App Store Connect wording must be reviewed against the production build, privacy policy, CloudKit access model, support site, and chosen AI service.

| Apple data type | Repository evidence | Purpose | Linked to identity | Tracking | Proposed answer / decision needed |
| --- | --- | --- | --- | --- | --- |
| Photos or Videos | User-selected or camera-captured photos are normalized, metadata-stripped, stored as `PhotoAsset` full and thumbnail JPEG data, and mirrored/shared through CloudKit with the Place graph. A Thing photo may be sent to the configured labeling service. | App Functionality | Potentially linked through the user's private/shared iCloud graph; confirm Apple's CloudKit treatment. | No tracking behavior exists in the repository. | Declare if Apple's rules treat the app's CloudKit persistence as developer collection. If live AI is enabled, reassess transmission and provider access/retention. |
| Other User Content | Place, Room, Storage Area, Container, and Thing names; Thing keywords and notes; QR associations; and user-created hierarchy are persisted and may be shared with invited participants. | App Functionality | Potentially linked through the iCloud graph; no separate WITT account exists. | No | Same CloudKit/legal determination as above. |
| User ID | WITT has no app-specific login or user profile. iCloud identity and participant management are provided by Apple frameworks; the repository does not persist an email address or Apple ID. | App Functionality for CloudKit/sharing | Apple-managed | No | Do not declare an app-specific User ID based on current code unless production operations expose or retain a CloudKit identifier that Apple's rules classify here. Confirm before submission. |
| Diagnostics | No analytics, crash-reporting SDK, custom diagnostic upload, or telemetry endpoint is represented in the repository. | None | No | No | Proposed `No`, subject to the final binary and any App Store/Xcode service settings outside the repo. |
| Usage Data | No analytics or usage-event collection is represented in the repository. | None | No | No | Proposed `No`, subject to final binary inspection. |
| Device ID | No advertising identifier, vendor identifier, or custom device identifier collection is represented in the repository. | None | No | No | Proposed `No`. CloudKit internals alone should not be recharacterized without reviewing Apple's current definitions. |
| Contact Info, Financial Info, Location, Health & Fitness, Browsing History, Search History, Purchases, Contacts, Sensitive Info | No collection is represented in the repository. User-entered location-like storage names describe household organization, not device geolocation. | None | No | No | Proposed `No`, subject to support-site practices and final production services. |

Repository-wide conclusions:

- No advertising, cross-app tracking, analytics SDK, data broker, or tracking permission exists in the repository.
- Camera access is used for QR scanning and photos. Photo-library access is user-initiated.
- Photo source metadata is stripped before persistence and labeling.
- Core Data uses private and shared CloudKit stores rooted at a Place.
- Sharing is private to invited participants with read/write access.
- The Responses-compatible labeling request disables provider response storage with `store: false`; raw provider responses and bearer tokens are not persisted or logged.
- Live AI remains disabled in an unconfigured Release build. Production enablement still requires Sid to approve a relay or short-lived credential strategy, provider/model, retention terms, privacy disclosure, and operational controls.

Required decisions before answering App Privacy:

1. `<SID/LEGAL: Does WITT's CloudKit-backed app data count as data collected by the developer under the current questionnaire and publisher access model?>`
2. `<SID: Will live photo labeling ship in this version?>`
3. `<PROVIDER: Identify relay/operator, model provider, transfer regions, access, retention, deletion, and training terms.>`
4. `<SID/LEGAL: Confirm whether private invited Place content is classified as User-Generated Content and whether any moderation disclosure is required.>`
5. `<SID: Confirm support form/email data handling and whether any external crash or analytics service is added outside this repository.>`

Do not finalize the questionnaire from this draft alone. Reconcile it with the archived binary's dependency inventory, entitlements, network behavior, public privacy policy, and the exact live questions immediately before submission.

## Apple References

Checked July 15, 2026:

- [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information) - app-name and subtitle limits, privacy-policy requirement, and shared app properties.
- [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information) - promotional text, description, keyword, and support-URL limits.
- [Upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots) and [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) - current count, formats, display classes, and pixel sizes.
- [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) - current collection, linked-data, CloudKit, and on-device-processing guidance.
