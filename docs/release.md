# WITT Release Reference

This page records durable distribution facts and the repeatable release process. Track release gates, TestFlight feedback, and other active work in [todo.md](todo.md).

## App Store Connect

| Field | Value |
| --- | --- |
| App record | `WITT: Where Is The Thing?`; requested rename to `WITT: Where Is That Thing?` is unavailable because Apple reports that name is used by another account |
| Apple app ID | `6789885351` |
| Bundle ID | `in.sids.witt` |
| CloudKit container | `iCloud.in.sids.witt` |
| Internal TestFlight group | `WITT Internal` |
| Current TestFlight build | 1.0 (7) |
| Source commit | `d723e9e` |
| App Store Connect build ID | `9d5cf61b-cd1a-40bb-b198-0c62cf2254c3` |
| Build state | `IN_BETA_TESTING` in `WITT Internal` with auto-notify enabled; FB-024 awaits confirmation on the affected device |
| Xcode / SDK | Xcode 27.0 (`27A5218g`) / iOS 27.0 |
| Minimum OS | iOS 26 |
| Non-exempt encryption | No |

## Release History

| Build | Source | App Store Connect ID | Internal state | Verification |
| --- | --- | --- | --- | --- |
| 1.0 (7) | `d723e9e` | `9d5cf61b-cd1a-40bb-b198-0c62cf2254c3` | `IN_BETA_TESTING` in `WITT Internal` | 145 simulator tests in Debug and clean Release-optimized configurations; arbitrary QR payload support and Browse creation-control polish; production CloudKit/push/TestFlight entitlements; minimum iOS 26; no non-exempt encryption; matching arm64 executable/dSYM UUID `8802BEB9-138D-3CCA-BAF0-C4E153AAA3E0`; What to Test and internal-group relationship verified; affected-device Container confirmation pending |
| 1.0 (6) | `66fe38f` | `fdd162af-54ce-4cc4-967c-eb6296dc9966` | `IN_BETA_TESTING` in `WITT Internal` | 134 simulator tests in Debug and Release-optimized configurations; production CloudKit/push/TestFlight entitlements; minimum iOS 26; no non-exempt encryption; matching arm64 dSYM; What to Test and internal-group relationship verified; affected-device Container confirmation pending |
| 1.0 (5) | `f34fead` | `f7c85715-461d-427b-ab52-72a0aab6aeb7` | `IN_BETA_TESTING` in `WITT Internal` | 132 simulator tests in Debug and Release-optimized configurations; release Container persistence regression; build-4 store compatibility; production CloudKit/push entitlements; matching dSYM; What to Test verified; affected-device confirmation pending |
| 1.0 (4) | `28433e3` | `54bf071a-76d5-4829-9067-326f003da172` | `IN_BETA_TESTING` in `WITT Internal` | 125 simulator tests; iPhone/iPad Browse and Search checks; production CloudKit/push entitlements; What to Test verified |
| 1.0 (3) | `bfd9324` | `a0a43fff-0531-4ba5-b1d8-aa9641866d48` | `IN_BETA_TESTING` in `WITT Internal` | 108 simulator tests; production CloudKit/push entitlements; What to Test verified |
| 1.0 (2) | `31c0b05` | `32aa0fa1-b951-4332-82a9-ee7e28ee5a40` | Valid in `WITT Internal` | First feedback build |

## Signing And Entitlements

- Archive the `witt` target with Release configuration, automatic signing, and the Apple Developer team selected for WITT.
- The signed product must use bundle ID `in.sids.witt` and CloudKit container `iCloud.in.sids.witt`.
- Preserve the iCloud CloudKit and remote-notification capabilities from `witt/WITT.entitlements` and `witt/Info.plist`.
- Confirm the distribution provisioning profile contains the production `aps-environment` entitlement after archive export. The source entitlement can show `development`; signing resolves the effective value for the selected profile.
- Keep `ITSAppUsesNonExemptEncryption` set to `false` unless the app's encryption use changes.
- Never embed provider credentials or release-service credentials in the app, project files, archive, or documentation.

## Release Checklist

1. **Choose the version and build number.** Keep `MARKETING_VERSION` at the intended release version and increment `CURRENT_PROJECT_VERSION` to a value not already uploaded. Confirm both Debug and Release settings for the app target agree.
2. **Verify the source.** Record the full source commit, ensure the intended changes are committed, run the complete `wittTests` suite, and perform the current device checks from [todo.md](todo.md).

   Before a TestFlight upload, also run the suite with Release optimization and testability enabled so whole-module optimization exercises the production code path:

   ```sh
   xcodebuild -project witt.xcodeproj \
     -scheme witt \
     -configuration Release \
     -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' \
     ENABLE_TESTABILITY=YES \
     test
   ```
3. **Select Xcode.** Use the Xcode version required for the iOS 26 SDK. If that is an Xcode beta, App Store Connect acceptance can vary during the beta cycle; confirm uploads from that build are currently accepted before treating the archive as releasable.
4. **Archive.** In Xcode, select a generic iOS device and use Product > Archive, or run:

   ```sh
   xcodebuild -project witt.xcodeproj \
     -scheme witt \
     -configuration Release \
     -destination 'generic/platform=iOS' \
     -archivePath '<ARCHIVE_PATH>/WITT.xcarchive' \
     archive
   ```

5. **Inspect the archive.** Verify version, build number, bundle ID, signing identity, provisioning profile, minimum OS, CloudKit entitlement, push entitlement, and `ITSAppUsesNonExemptEncryption = false`.
6. **Export for App Store Connect.** Use Organizer's Distribute App flow, or an App Store Connect export-options plist maintained outside the repository:

   ```sh
   xcodebuild -exportArchive \
     -archivePath '<ARCHIVE_PATH>/WITT.xcarchive' \
     -exportPath '<EXPORT_PATH>' \
     -exportOptionsPlist '<EXPORT_OPTIONS_PLIST>'
   ```

7. **Upload.** Upload through Xcode Organizer or the installed `asc` CLI. Supply authentication through the uploader or credential store; do not place credentials in commands committed to the repository.

   ```sh
   asc builds upload \
     --app 6789885351 \
     --ipa '<IPA_PATH>' \
     --test-notes '<WHAT_TO_TEST>' \
     --locale en-US \
     --wait
   ```
8. **Wait for processing.** In App Store Connect, confirm the uploaded build reaches `Valid`, reports minimum iOS 26, and reports no non-exempt encryption. Record the source commit and App Store Connect build ID with the release facts.
9. **Assign the internal group.** Resolve the group ID, add the processed build to `WITT Internal`, and confirm any required compliance answer before enabling testing.

   ```sh
   asc testflight groups list --app 6789885351 --internal --paginate
   asc builds add-groups --build-id '<BUILD_ID>' --group '<WITT_INTERNAL_GROUP_ID>'
   ```
10. **Set What to Test.** Describe the user-visible changes and focused regression areas for this build. Include the QR scan/bind/add flow, photo capture and selection, Browse/Search management, printable QR output, and Place sharing when those surfaces changed. Do not include credentials, private account details, or internal artifact paths.
11. **Smoke test from TestFlight.** Install the distributed build on supported iPhone and iPad hardware, launch cleanly, exercise the changed workflows, and capture all findings in [todo.md](todo.md).

## Release Record Template

For each uploaded build, retain these durable facts in the release history or commit that updates this page:

- Version and build: `<VERSION> (<BUILD_NUMBER>)`
- Source commit: `<GIT_COMMIT>`
- App Store Connect build ID: `<BUILD_ID>`
- Upload and processing result: `<STATE>`
- Xcode and SDK: `<XCODE_VERSION> / <SDK_VERSION>`
- TestFlight groups: `<GROUP_NAMES>`
- What to Test summary: `<SUMMARY>`
- Verification result: `<TEST_AND_DEVICE_RESULT>`
