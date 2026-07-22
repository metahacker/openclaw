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
