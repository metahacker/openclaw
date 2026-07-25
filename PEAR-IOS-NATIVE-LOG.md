# PEAR iOS Native UX — Build Log

Overnight lane, 2026-07-22. Mission: replace the bootleg-webview TestFlight app with a native SwiftUI
implementation of the Playground world UX (prototype 2026-07-21), keeping all OpenClaw node
functionality and demoting the WebView to a "Classic view" fallback.

## 2026-07-22 ~10:10 UTC — Recon complete, branch created

- Read tonight's design record (`working-state.md`), prototype HTML/CSS (palette, card grammar,
  intimate chat, truth line), field spec, and the shipping app source.
- Build path confirmed: `.github/workflows/ios-pear-app.yml` → xcodegen + fastlane `beta` on
  macos-26 runners; triggers on push to `pear-ios-hello-testflight` or `workflow_dispatch`
  (dispatchable against any branch via `--ref`). MARKETING_VERSION is hardcoded in the workflow env —
  bumping it there to 2026.7.22 (mission-authorized).
- CI runs `swiftformat --lint` + `swiftlint` as pre-build scripts against
  `SwiftSources.input.xcfilelist`; new Swift files must be appended there.
  Note: `scripts/ios-write-swift-filelist.mjs` referenced in the brief does **not** exist in the
  repo — the filelist is hand-maintained (64 entries). Appending by hand.
- Auth recon (server source readable at /home/pear-web/playground, read-only):
  - `/api/home/feed` → 401 today (other lane still building it). Client will try it first with the
    device key and fall back gracefully.
  - Open (no auth): `/api/briefing` (queued/inMotion, real shapes sampled),
    `/api/status/data` (projects with slug/emoji/health/freshness/updatedAt/summary),
    `/api/apps/registry`.
  - Device-key lane (`Bearer` header or `?k=`): `/api/pear-mobile/ping`, `/api/pear-mobile/chat/history`,
    `/api/pear-mobile/chat/send`. The key arrives via `openclaw://playground?k=…` deep link
    (Safari handoff) — currently only forwarded to the WebView `/auth/device` exchange; will also
    persist it to the Keychain for the native client.
- Branch `pear-ios-native-ux` created off `pear-ios-hello-testflight` HEAD (4dbc95a03d3).
  Pre-existing dirty WIP (src/channels/\*, voice-patches/) left untouched, will never be committed.

## Plan of record

1. `apps/ios/Sources/Pear/*`: theme (cream/espresso palettes from prototype), typed API client +
   models, store with home-feed→fallback composition, tab shell (Home · Chats · Projects · Apps · ⋯),
   Home stream, Chats + conversation with Field composer + truth line, wiki project views, Apps grid,
   backstage (Classic view = existing RootCanvas fullscreen cover, Settings, node status).
2. Root swap in OpenClawApp; deep-link key persistence in NodeAppModel (small diff).
3. Filelist + workflow (version 2026.7.22 + branch trigger), commit apps/ios + workflow only.
4. Push → dispatch `ios-pear-app.yml` → fix compile errors from run logs until green + TestFlight.

## 2026-07-22 ~10:40 UTC — Native shell implemented (first cut)

- New `apps/ios/Sources/Pear/` (10 files): PearTheme (prototype palette light/dark, serif/mono type
  ramp, glowing presence dot, card grammar), PearAPI (typed client; Bearer device key),
  PearStore (home feed → honest fallback composition from briefing+status), PearChatModel
  (pear-mobile chat lane, truth line reflects real send state), PearRootShell (5-tab shell +
  node plumbing: trust prompts, deep-link prompts, camera flash, node ChatSheet, classic cover),
  PearHomeView (In motion + day-grouped stream + link-device card), PearChatsView (threads +
  intimate conversation + Field composer pill), PearProjectsView (index + wiki-style detail),
  PearAppsView (tile grid), PearBackstageView (Classic view / Node chat / Settings / honest state
  rows).
- Wiring diffs kept small: OpenClawApp root → PearRootShell; NodeAppModel persists the Playground
  device key to Keychain on the `openclaw://playground?k=` deep link (WebView exchange unchanged);
  filelist +10 entries; workflow MARKETING_VERSION → 2026.7.22 + push trigger for this branch.
- Verified locally: CI's swiftformat gate skips apps/ios entirely (root `.swiftformat` excludes it;
  reproduced with the same command CI runs — "74 files skipped"). SwiftLint gate does run; code
  matches existing style and only warning-level rules are implicated. Swift compilation cannot be
  checked on this Linux box — CI is the compiler from here.
- Honest limitations in this cut: conversation drill-down for "in motion" threads reuses the single
  pear-mobile chat lane with a context label (no per-thread API on the open lane yet); project
  detail composes pages from feed items matching the project hashtag and links out to the full
  wiki; `/api/home/feed` still 401 server-side so the app will run on fallback until that lane
  ships (client already prefers the feed when it appears).

## 2026-07-22 10:30 UTC — GREEN + SUBMITTED (gates)

1. **CI green, first compile**: run 29911426497 and 29911511344 were superseded by quick follow-up
   pushes (async-let hardening, status-bar fix) before their build steps mattered; definitive run
   **29911571727** = SUCCESS end-to-end (xcodegen → build → sign → export).
   https://github.com/metahacker/openclaw/actions/runs/29911571727
2. **TestFlight**: fastlane log — "Successfully uploaded package to App Store Connect… Successfully
   uploaded the new binary" at 10:28:14Z. **PEAR 2026.7.22 (build 21)**, branch pear-ios-native-ux,
   head ca3263a122a. (Upload uses skip_waiting_for_build_processing; ASC-side processing state not
   observable from this box — the key lives only in GH secrets. Expect it visible in TestFlight
   within minutes, as with prior builds on this lane.)
3. **WebView demoted, alive**: ⋯ → Classic view presents the untouched RootCanvas fullscreen; the
   shell also auto-surfaces it whenever the gateway or connect deep link navigates the canvas.
4. **Node functionality untouched by diff**: full branch diff = new Pear/ directory + 3 additive
   lines in NodeAppModel (Keychain persist of device key) + RootCanvas→PearRootShell root swap +
   filelist + 2-line workflow change + this log. No deletions in node/gateway code. Pre-existing
   uncommitted WIP (src/channels/\*, voice-patches/) never staged, still dirty in the worktree.
5. **Honest limitations**: no on-device/simulator run was possible from this Linux lane — the UI has
   compiled and shipped but nobody has _seen_ it yet; the Chats drill-down for "in motion" threads
   is the single pear-mobile lane with a context label; /api/home/feed still 401 server-side, so
   Home runs on the projects fallback until that lane ships (client flips over automatically);
   swiftformat's CI gate skips apps/ios by root config — style verified by eye against siblings.

Frozen on green. Next natural steps when humans wake: install build 21, walk the five tabs, link
device via Safari handoff, and decide whether the home stream fallback reads right until the feed
API lands.

## 2026-07-22 ~18:55 UTC — First human eyes found the launch bug (fix → build 22)

- Alex installed build 21: "it seems unchanged i just get the web view." Root cause found in
  minutes: `showA2UIOnConnectIfNeeded()` auto-navigates the canvas on every gateway connect, and
  PearRootShell watched `screen.urlString` — so on a paired phone the classic fullscreen WebView
  covered the native shell within seconds of launch. The native app was there the whole time,
  underneath, with only the small "Back to app" pill at bottom-left giving it away.
- Fix (PEAR main thread, surgical): new `NodeAppModel.canvasCommandNonce` (mirrors the
  cameraFlashNonce pattern) bumped ONLY by explicit gateway canvas intent — canvas.present
  (non-empty url), canvas.navigate, a2ui.reset after ready. `showA2UIOnConnectIfNeeded()` and
  session restore never bump it. PearRootShell now watches the nonce instead of the raw URL, so
  launch lands in the native shell and agent-driven navigation still surfaces Classic view.
- Node functionality untouched beyond the three additive nonce bumps; no deletions.
  2026-07-22T00:00:00-07:00 lane started: iOS native lane resumed on pear-ios-native-ux at HEAD 2324ab2 for Google OAuth persistent login and Playground-design polish.
  2026-07-22T13:42:57-07:00 milestone 1 reads: confirmed the server's durable Playground auth is `pear_session` in `playground.sessions`; `/connect/app` requires a real web Google login via `/auth/login` when missing, then returns `openclaw://playground?k=…`; `/auth/device?k=…` mints a `pear_session` Set-Cookie for the app. No playground edit needed. Native gap is to open that broker with ASWebAuthenticationSession, exchange the key natively, persist `pear_session`, and send it as Cookie on every API call. Also found real `/api/home/feed` shape is `in_motion` + `stream` + `shelves`, not the first-cut guessed `days/items/inMotion`, so decoding must be corrected with auth.
  2026-07-22T13:53:01-07:00 milestone 1 implementation checkpoint: added Keychain-backed `PearSessionStore`, ASWebAuthenticationSession Google broker login, native `/auth/device` Set-Cookie capture, automatic legacy device-key-to-session upgrade on launch/deep-link, and cookie injection on all PearAPI calls. Home now decodes authenticated `in_motion`/`stream` feed and only marks live feed when `visibility=all`; Projects uses `/api/projects` plus project wiki `/api/projects/:id/sites`; Chats uses authenticated `/api/chat/conversations` and page-scoped `/api/chat` history/send, with pear-mobile Bearer key kept as fallback. Local `git diff --check` and line-length/large-tuple scans are clean; no Swift toolchain exists on this Linux box, so CI is still the compiler.
  2026-07-22T14:18:58-07:00 compile verification started: oriented from checkpoint 21a4397e (`PearAuth.swift`, authenticated `PearAPI`, store/view wiring) plus the lane log tail. Dispatching one `ios-pear-app.yml` CI run on `metahacker/openclaw@pear-ios-native-ux` to verify milestone 1 compiles before any Playground polish.

## 2026-07-22 19:35 PT — PEAR (main) dispatched the I1 verify build directly

- The ios-verify lane was slow to act, so PEAR dispatched the OAuth compile-verification build itself:
  CI run 29974779646 (in_progress) on pear-ios-native-ux HEAD 21a4397e.
  https://github.com/metahacker/openclaw/actions/runs/29974779646
- LANE/WATCHDOG: do NOT dispatch another build until this one finishes (Apple cert cap). Watch run
  29974779646; if it FAILS, read the compile errors and fix under apps/ios with scoped commits, then
  re-dispatch ONE build. If GREEN, log the TestFlight build number — that's the I1 gate.

## 2026-07-24 — I2 (iOS polish + logo): official PEAR pear app icon

- Ground-truth on entry: origin/pear-ios-native-ux tip = 2324ab2; CI run #23 (id 29974779646,
  GREEN) built sha 2324ab2 via workflow_dispatch = TestFlight build 23. The OAuth WIP commit
  21a4397e was local-only and had NOT been CI-compiled (run 23's "HEAD 21a4397e" label was
  inaccurate; the dispatch ran the pushed branch tip 2324ab2). So this push is the first CI compile
  of the OAuth milestone as well.
- Design language (calm/warm/cream, serif) was already applied across all 5 native surfaces in the
  native-shell milestone (PearTheme + Pear/\*View), so I2's remaining concrete deliverable was the
  official logo as the app icon.
- App icon rebuilt from the official PEAR vector (client/src/assets/pear-logo\*.svg + PearLogo.tsx),
  NOT invented: took the pear body + stem paths, removed BOTH leaf paths (big tan leaf M200.449 and
  small green leaf M136.753), derotated the mark 195° so it sits at the 🍐 emoji angle (stem up,
  round bottom, slight right lean), and centered it on the cream ground (--cream #FAF6EF) using the
  sanctioned "positive" pear colors for a light background (body #909D15, stem #B48C64). Leaf-removed
  - derotated per chat/app-icon doctrine.
- Regenerated every PNG in Sources/Assets.xcassets/AppIcon.appiconset (28 files, 20→1024) at exact
  sizes, opaque RGB (color-type 2, 8-bit, no alpha) so the CI icon-verification gate passes; ran the
  CI's own Python check locally = PASS. Reads clearly down to 40px. WatchApp assets left untouched
  (watch target is dropped in v1 CI). No Swift/code changes — pure asset regen; zero compile risk
  from the icon itself.
- Push carries 21a4397e (OAuth, first CI compile) + this icon commit → auto-triggers ios-pear-app.yml
  (paths apps/ios/\*\*). Expected next run #24 → BUILD_NUMBER 24. I2 is NOT done: final gate is Alex's
  eyes on TestFlight.

## 2026-07-25 — CORRECTION (per Alex): app icon = FULL official PEAR logo, leaf ON, normal orientation

- Alex correction: the iOS APP ICON must use the full official PEAR logo WITH the leaf, in NORMAL
  (non-derotated) orientation. Stripping the leaf and derotating to the emoji angle is ONLY for
  emoji-style icons (e.g. the web chat widget), NOT the app icon. The prior build (commit 3a533279d,
  "build 24") wrongly removed both leaf paths and derotated the mark 195 degrees. This reverses that.
- Rebuilt the master from ALL FOUR official mark paths (PearLogo.tsx / pear-logo-positive.svg),
  NORMAL orientation (no rotate), positive palette: body M105.514 #909D15, stem M111.306 #B48C64,
  big leaf/tan lobe M200.449 #B48C64, small green leaf/accent M136.753 #909D15. Rendered via
  rsvg-convert at 1600px, trimmed, composed centered on cream #FAF6EF (mark fit within 640px of the
  1024 canvas for comfortable padding).
- Regenerated all 28 PNGs (20 to 1024) at exact sizes, opaque RGB (PNG color-type 2, no alpha). Ran
  the CI's own Python check locally (the "Verify iPad support and PEAR icon catalog" step) = PASS,
  plus an extended sweep of all 28 declared files (exact size + no alpha) = PASS. Pure asset regen.
- Build-24 invisibility investigation (fixed in a separate scoped commit): the app was missing
  ITSAppUsesNonExemptEncryption, so App Store Connect parks every upload in "Missing Compliance"
  (invisible to testers) until answered by hand, and fastlane's skip_waiting_for_build_processing:true
  masks it (CI logs "Successfully uploaded the new binary" regardless of the parked state). Fix: added
  ITSAppUsesNonExemptEncryption=false to the app target info.properties in project.yml so future
  uploads (incl. this one) go straight to testers. BUILD_NUMBER is github.run_number (strictly
  increasing) so there is no CFBundleVersion collision for MARKETING_VERSION 2026.7.22.
- Push triggers the next ios-pear-app.yml run; BUILD_NUMBER = that run_number. NOT done: final gate is
  Alex's eyes on TestFlight.
