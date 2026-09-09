# PEAR One Living Surface experiment

This is the isolated PEAR fork of current OpenClaw iOS, not the upstream App Store release. `release.json` binds its existing app/team, source baseline, marketing version, experiment branch, and beta notes. App icon and `PearMark` are the exact approved full PEAR mark from the previous fork; they are not regenerated.

## One entry, no fallback

The active registered workflow is `.github/workflows/ios-pear-app.yml` (GitHub workflow ID `309078312`). Its contents on this feature branch are manual-only. The default branch workflow is unchanged.

Dispatch the feature ref with its full reviewed source commit and `upload=false` first. `upload=true` requires the same simulator proof before introducing existing protected signing credentials. All release actions still go through `pnpm ios:release:upload`; `PEAR_OLS_EXPERIMENT=1` selects the explicitly gated PEAR lane. The normal official OpenClaw `release_upload` route is unchanged. There is no lower-level fallback after failure.

The current upstream uploader cannot accept this app as configuration alone: it rejects non-OpenClaw teams, pins official App Store bundle IDs/signing repository, and requires the official push relay identity. The fork adaptation preserves the source, simulator, screenshots, monotonic Apple allocation, signed IPA, upload, and processing gates without writing official metadata or submitting review.

## Proof and distribution

- The secretless job builds current native iOS plus its unchanged target graph, runs `PearOLSTimelineTests` and `PearOLSUITests`, then captures the `--pear-ols-screenshot` synthetic surface on iPhone and 13-inch iPad.
- Proof is bound by full source SHA and screenshot hashes. Runtime mock/synthetic screenshots are explicitly not authenticated-device evidence.
- Release verifies existing App Store Connect app ID against the protected bundle identifier and the recorded metahack team. It does not create an app, tester, or group.
- Every Apple `buildUploads` attempt, including failed attempts, consumes its number. Unknown or in-flight upload state fails closed. Allocation is reread just before the only upload attempt; the existing PEAR distribution workflow concurrency group serializes runs and never cancels an uploader.
- The lane assigns only an existing internal `PEAR Team` (or historic `Internal Testers`) group, never an external group; it verifies `VALID`, `IN_BETA_TESTING`, and group assignment independently. No App Review, external Beta Review, public-link creation, or public metadata update occurs.
- A failed upload/verification leaves `release-receipt.json` with its last verified stage. Reconcile the exact Apple state before a new run; never equate a green archive with TestFlight readiness.

## Native capabilities remain present

Preparation derives a separate generated XcodeGen spec without removing targets or dependencies: Watch, share extension, Live Activity widget, app groups, and HealthKit remain. This may expose missing historical PEAR App IDs/profiles/capabilities during signing. Report those exact failures; do not strip capabilities to force a green build. The archive verifier requires all three companion products.

Push mode remains `localProduction` for the PEAR fork; it does not impersonate the official OpenClaw hosted relay distribution. Authenticated chat, voice/audio routes, push behavior, permissions, and real-device performance require their own live verification before claiming those capabilities work.

The full current upstream Watch build requires Rust `nightly-2026-09-05` with `rust-src`. The workflow pins Node24.19.0, pnpm12.3.4, Ruby3.4.10/Bundler2.6.9, the checked-in Fastlane lock, SwiftFormat0.63.0, SwiftLint0.65.1, and uses the newest installed Xcode26+.
