# PEAR One Living Surface experiment

This is the isolated PEAR fork of current OpenClaw iOS, not the upstream App Store release. `release.json` binds the separate **PEAR MVP** app (`bundleId`, `appId`, `teamId`), source baseline, marketing version, experiment branch, and beta notes. App icon and `PearMark` are the exact approved full PEAR mark from the previous fork; they are not regenerated.

The experiment never ships into the original PEAR app (App Store Connect app `6759186465`). The release identity is source-controlled in `release.json`; the `IOS_BUNDLE_ID` secret still names the original app and is used only as a forbidden value. `prepare.py`, `verify-ipa.py`, and `PearOLSFastfile` fail closed while `appId` is empty, when it equals the original app, or when the bundle matches the original bundle. Build numbering starts fresh on the new app record.

## One entry, no fallback

The active registered workflow is `.github/workflows/ios-pear-app.yml` (GitHub workflow ID `309078312`). Its contents on this feature branch are manual-only. The default branch workflow is unchanged.

Dispatch the feature ref with its full reviewed source commit and `upload=false` first. `upload=true` requires the same simulator proof before introducing existing protected signing credentials. All release actions still go through `pnpm ios:release:upload`; `PEAR_OLS_EXPERIMENT=1` selects the explicitly gated PEAR lane. The normal official OpenClaw `release_upload` route is unchanged. There is no lower-level fallback after failure.

The current upstream uploader cannot accept this app as configuration alone: it rejects non-OpenClaw teams, pins official App Store bundle IDs/signing repository, and requires the official push relay identity. The fork adaptation preserves the source, simulator, screenshots, monotonic Apple allocation, signed IPA, upload, and processing gates without writing official metadata or submitting review.

## Proof and distribution

- The secretless job builds current native iOS plus its unchanged target graph, runs `PearOLSTimelineTests` and `PearOLSUITests`, then exports the retained in-test `--pear-ols-screenshot` attachment on iPhone and 13-inch iPad. An outer simulator screenshot after XCTest exits is rejected because it only captures the Home screen.
- The generated shipping spec explicitly enables Apple's **Mac (Designed for iPad)** path for the app, share extension, and activity widget. This makes the same iPhone/iPad binary eligible on Apple-silicon Macs; it does not add a Catalyst or native macOS target.
- Proof is bound by full source SHA and screenshot hashes. Runtime mock/synthetic screenshots are explicitly not authenticated-device evidence.
- Release verifies the `release.json` App Store Connect app ID carries the PEAR MVP bundle identifier and the recorded metahack team. It does not create an app, tester, or group; the internal `PEAR Team` group must already exist on the PEAR MVP app.
- Every Apple `buildUploads` attempt, including failed attempts, consumes its number. Unknown or in-flight upload state fails closed. Allocation is reread just before the only upload attempt; the existing PEAR distribution workflow concurrency group serializes runs and never cancels an uploader.
- The lane assigns only an existing internal `PEAR Team` (or historic `Internal Testers`) group, never an external group; it verifies `VALID`, `IN_BETA_TESTING`, and group assignment independently. No App Review, external Beta Review, public-link creation, or public metadata update occurs.
- A failed upload/verification leaves `release-receipt.json` with its last verified stage. Reconcile the exact Apple state before a new run; never equate a green archive with TestFlight readiness.

## Native capabilities remain present

Preparation derives a separate generated XcodeGen spec without removing targets or dependencies: Watch, share extension, Live Activity widget, app groups, and HealthKit remain. This may expose missing historical PEAR App IDs/profiles/capabilities during signing. Report those exact failures; do not strip capabilities to force a green build. The archive verifier requires all three companion products.

Push mode remains `localProduction` for the PEAR fork; it does not impersonate the official OpenClaw hosted relay distribution. Authenticated chat, voice/audio routes, push behavior, permissions, and real-device performance require their own live verification before claiming those capabilities work.

The full current upstream Watch build requires Rust `nightly-2026-09-05` with `rust-src`. The workflow pins Node24.19.0, pnpm12.3.4, Ruby3.4.10/Bundler2.6.9, the checked-in Fastlane lock, SwiftFormat0.63.0, SwiftLint0.65.1, and uses the newest installed Xcode26+.
