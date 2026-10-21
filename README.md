# PVLDS — Project VR Launcher That Doesn't Suck

A VR-first launcher for VPX (Visual Pinball) tables: put the headset on,
stand in front of your collection, pick a table, play. Built with
Godot 4.7 + OpenXR for PCVR (Quest 3 via Virtual Desktop / VDXR first;
SteamVR runtime is a later test target).

**Status: M2 — "The hand-off" (built 2026-10-21; two fix rounds
the same day, after the first real-hardware sessions).** M1's room
plus real launching: card-level Launch, a native watchdog that
returns you to the room with your place restored, focus herding,
and Exit-to-desktop. The first session proved the launch and the
watchdog's return trip on Chris's rig; it also caught two defects
the first fix round addressed — quitting a table landed in the
VPX editor with the process still alive (fixed, wrongly, by
adding `-exit` to the template: see below), and the launcher
vanished the instant VPX spawned, leaving a desktop gap during
VPX's ~20s load (the launcher now stays in the room until the
hand-off). The second fix round — the corrected one — repairs
the `-exit` damage and gives the watchdog the session-close duty
(the ecosystem's actual pattern: the frontend closes VPX). The
M2 gate remains an evening of real tables on Chris's machine —
nothing here claims the Windows/VPX/VDXR hand-off works until he
says so. Design of record: `~/workspace/vpx-vr-launcher/design.md`
(outside this repo).

## The hand-off (M2)

- **Launch.** Every wall panel carries a **LAUNCH** button (the card
  itself still opens the detail view — More Info). The detail view's
  Play fires the same path, including its play-once / make-default
  build choice. Launching uses the player's **default build** and
  the config's **launch-args template** (`{table}` expands to the
  build's full path; quotes in the template group arguments — never
  a hard-coded command line). The shipped default template is
  `-play "{table}"`. **There is no `-exit` flag**: one fix round
  shipped it from frontend folklore, and on the rig VPX read
  `exit` as a table filename and errored. In vpinball's own parser
  the token is a no-op "(ab)used by frontend, not handled by us"
  (`src/core/AppCommands.cpp`) — exiting a table lands in the VPX
  editor by design, and the watchdog's session-close duty (below)
  is what finishes the trip. A saved template byte-identical to
  the bad string (`-play -exit "{table}"`) was our dictation,
  never a customization, and is repaired to the good default on
  load; any other template is the player's and is never
  rewritten.
- **The launcher stays for the load.** On launch the launcher
  records state (recents, last-played, room view), writes the
  watchdog session contract in the **loading** state, spawns VPX
  detached — and **stays in the room**: the launched panel reads
  LOADING..., every other Launch is disabled (no double launches),
  EXIT stays live. The launcher exits at the hand-off, the first
  of: (a) the watchdog's contract reports VPX's main window exists,
  plus a ~1.5s settle; (b) the launcher's own XR session reports it
  is ending (VPX is taking the headset over); (c) a 45s hard cap,
  so the room can never hang on a stuck load. As it exits it marks
  the session **live**. If VPX dies during the load instead, the
  session is marked **failed**, nobody relaunches anything, and
  the resident launcher flags the panel FAILED and returns to
  normal browsing. EXIT during the wait disarms the session
  entirely (VPX keeps loading, detached; its later exit resurrects
  nothing) and quits. After the hand-off the launcher is fully
  gone — no resident mode; absence remains the fix for the XR/
  focus fights.
- **The watchdog** (`watchdog/`, Go, stdlib only) is a separate tiny
  native process. The launcher starts it on boot (single-instance:
  a second start hands over via the contract file and exits). It
  polls `pvlds_watchdog_contract.json` in the app's user data dir
  and runs the session state machine: in **loading** it stamps
  `game_window_seen_unix` when the game's main window appears and,
  if the game dies, either marks the session **failed** (the
  supervising launcher is still resident — it owns the failure) or
  promotes the session to **live** (the launcher is gone — a
  launcher that died mid-wait must never strand the player at a
  dead desktop). In **live** it waits for the game process to die
  (exit or crash — same handling) and relaunches the launcher
  **once**. The relaunched launcher restores filter/sort/page with
  the just-played table selected. It never auto-relaunches a
  table. A log lands beside the contract (`pvlds_watchdog.log`).
- **Session-close duty** (Windows, user32; decision logic shared
  and unit-tested on Linux): in a **live** session, a table exit
  leaves VPX sitting in its editor — process alive, player window
  gone. The watchdog detects exactly that composite state and
  closes VPX, orderly, so the return trip can finish. The
  discriminator is grounded in the vpinball source: the player's
  SDL windows carry class **`VPPlayer`** (`SDL_RegisterApp` in
  `src/core/VPApp.cpp`), the editor frame's class is **`VPinball`**
  (`WinEditor::PreRegisterClass`); player-class gone AND
  editor-class present, sustained ~2.5s (a transient window
  shuffle is not an exit), fires once per session. Close method,
  in order: (1) the **PinSim::FrontEndControls** terminate
  request — the published protocol modern VP implements
  (registered window message, wParam 2 = CLOSE_APP, reply 1 =
  acknowledged; PinballY's `Application.cpp` is the reference
  sender); (2) **WM_CLOSE** to the editor window — which VP's own
  editor refuses while a player is open (`WinEditor::OnClose`),
  so it can only land in the state this duty targets. Never a
  hard kill; if neither lands, the watchdog logs it and leaves
  VPX alone. Kill-switch: the **Close VPX when a table exits to
  the editor** checkbox on the desk pass (config
  `close_vpx_on_table_exit`, default on) — uncheck it if you ever
  want to stay in the editor after a table.
- **Focus herding** (Windows, user32): while a session is live, if
  the foreground leaves the game process and stays away past a 2s
  grace period, the watchdog hands foreground back to the game's
  main window (rate-limited; it never moves or resizes windows).
  **It yields to deliberate use**: if the same foreign window is
  back in front after 3 re-assertions against it, herding stands
  down for the rest of that session and logs it — a player working
  at the desktop (say, clearing an error dialog) is never fought.
  The decision logic is shared and unit-tested on Linux
  (`herd_logic.go`); the next session starts fresh. Kill-switch:
  the **Focus herding** checkbox on the desk pass (config
  `focus_herding`, default on). If it ever fights you, uncheck
  it.
- **Exit.** The rail's **EXIT** disarms the watchdog and quits —
  the player who wants out stays out. Closing the window does the
  same. Hygiene: the watchdog also stands down if the contract
  file disappears, if the launcher hasn't checked in for 24h, and
  after 3 fast-death relaunches (loop cap — it disarms rather than
  resurrect-loop).
- **Delivery.** The watchdog is a build artifact, not a commit:
  `watchdog/build.sh` cross-compiles `pvlds_watchdog.exe` (and a
  host binary for tests) into `watchdog/build/` (gitignored). The
  exe must sit **beside the launcher exe** — that's where the
  launcher looks first (then `$PVLDS_WATCHDOG_PATH`, then the repo
  dev path). Ship `PVLDS.exe` + `pvlds_watchdog.exe` together.
- **Lazy XR.** The desk pass never touches OpenXR; XR initializes
  when the room is entered, and `xr/openxr/startup_alert` is off —
  flat launches no longer pop the "OpenXR was requested but failed
  to start" alert when no runtime is up.

## What M1 does

- **Library core (UI-independent).** Scans the configured table folders
  recursively for `.vpx` files, groups duplicate builds of the same
  game, and matches them against a cached VPS database (`vpsdb.json`,
  Virtual Pinball Spreadsheet format). Matching ladder: exact file name
  in the db → game by normalized title + build by version token →
  single-build shortcut (only when the file name states no version) →
  game-only → filename-only. A build whose stated version matches
  nothing in the db stays local-only; it is **never** relabeled as a db
  build.
- **Scans never block the UI, and art is lazy.** The scan (db load +
  folder walk + matching) runs on a WorkerThreadPool task with live
  progress in both routes that trigger it (desk Save & Scan, and the
  configured auto-boot, which presents the desk as a shell and enters
  the room when results land). Extracting a backglass from a
  `.directb2s` costs ~200 ms per file at real-world sizes, so the scan
  records only directory-listing facts (a same-stem image or
  `.directb2s` exists); extraction happens on first display of that
  game's panel/detail via `GameEntry.ensure_art()`, cached in
  `user://art_cache`. (Field fix, 2026-10-20: the original eager,
  main-thread scan froze the app for over a minute at 300 tables.)
- **Versions, visible.** Panels carry a "N BUILDS" chip. The detail
  view lists every build (version, author, date) with **CURRENT** (the
  build that matters: a db-known build outranks a local-only one; then
  latest date, then highest version) and **DEFAULT** (the player's
  pick, star-stored per game) chips. Selecting another build offers
  *Play This Once* or *Make Default*. Play always targets the default
  (or the armed once-build) — never a silently different twin.
- **The room.** Seated-first curved panel wall (12 panels per page),
  art where an image exists — side image beside the `.vpx` first, then
  the backglass extracted from a same-stem `.directb2s` (best-effort,
  cached in `user://art_cache`; any failure falls through) — and
  generated type-forward title cards everywhere else (manufacturer
  color band, big name, year/designer). Filters: All / VR / Favorites /
  Recents (VR is the default view). Sorts: name, year, manufacturer,
  designer.
- **One input model.** VR controller laser, mouse ray, and
  gamepad/keyboard focus all pick from the same surfaces. Mouse can
  drive the whole UI flat at the desk — the flat camera is static at
  the seated viewpoint and the mouse is a pure pointer (round-2 field
  fix: a view that drifts with the cursor makes click targets swim).
- **First-run desk pass.** A flat 2D setup (never in-headset): point
  at the VPX executable (`VPinball_GL64.exe` expected) and the table
  folder(s), optionally a cached `vpsdb.json`. Its **Download VPS
  database** button fetches the real `vpsdb.json` from the Virtual
  Pinball Spreadsheet project and caches it in `user://`. Database
  selection order for a scan: your chosen path, then the downloaded
  cache, then — last resort — the bundled sample; if the sample is
  what a scan used, the summary says so in plain language, because
  the sample cannot identify real tables. The desk pass writes a
  plain JSON config, runs the scan, and reports what the scan
  measured — duplicates, match rate, art coverage, unidentified
  titles.
- **No empty rooms.** If the active filter matches nothing in a
  non-empty library, the wall falls back to ALL and the banner says
  why. VR remains the default filter only when VR-tagged games
  exist.
- **State** (favorites, default builds, recents, last-played, and
  the room's filter/sort/page/selection) persists as plain JSON in
  `user://pvlds_state.json` — it is what the M2 return trip restores
  from. From M2, recents records launches (detail opens still count
  as touches while browsing).
- **`.ini` files are sacred.** The launcher never reads, writes,
  moves, or regenerates table `.ini` files. Its own config lives next
  to the executable (or `user://` in editor runs), never in table
  folders; art extraction caches to `user://` too.

## Running it

- **Editor:** open the project in Godot 4.7 and F5. No config → the
  desk pass opens. Use its "Use the bundled dummy library" button to
  run the whole flow on invented tables.
- **Export:** the "Windows Desktop" preset writes `../builds/PVLDS.exe`
  relative to the project (i.e. `~/workspace/builds/`); a "Linux"
  preset writes `../builds/PVLDS_linux` (used for in-VM end-to-end
  smokes of the hand-off). Copy `watchdog/build/pvlds_watchdog.exe`
  beside the Windows exe before shipping — see "Delivery" above.

## Dummy data

`dummy_data/tables/` holds 13 placeholder `.vpx` files (plain text —
not real tables) plus two side-image PNGs and one crafted `.directb2s`
with an embedded image, and `data/vpsdb.json` is an invented 10-game
database in the real VPS format. Every name, maker, and designer in
them is made up. Point the config at a real table folder and a real
cached `vpsdb.json` and the same code runs your actual library.

## Dev hooks (Godot user args, after `--`)

- `--pvlds-core-test` — UI-free test suite over the library core
  (scan/group/match/art/state) against the dummy data; prints
  ok/FAIL lines and exits 0/1.
- `--pvlds-seed-dummy` — boot straight into the room on the dummy
  library (pair with `--quit-after N` for headless smoke runs).
- `--pvlds-shot <path.png>` — with `--pvlds-seed-dummy`: once the
  room's textures settle, save a viewport screenshot to the path and
  quit. The layout QA loop (needs a real rendering driver, e.g.
  `--rendering-driver opengl3`, not the dummy one).
- `--pvlds-db-stats <path>` — load a `vpsdb.json`, print game /
  VPX-file / VR-tagged-file counts, quit.
- `--setup` — force the desk pass even when a config exists.
- `--pvlds-smoke-launch <game_id>` — boot (real installed config if
  one exists, else the seeded dummy), and when the scan lands, run
  the real launch path for that game's default build. The smoke
  rides the real hand-off wait and prints its verdict with the
  elapsed time: handed off (and why) = exit 0, failed load = exit
  1. Config exe/args can be overridden with the `PVLDS_SMOKE_EXE` /
  `PVLDS_SMOKE_ARGS` environment variables. This is the
  launcher-side integration smoke; the assembled round trip
  (exported binary + watchdog + a stub VPX that "loads" for a few
  seconds before its window exists) was verified the same way
  under Xvfb, including the failed-load variant.
- `--pvlds-shot-launch <path.png>` — with `--pvlds-seed-dummy`:
  once the wall is up, fire a real launch (same env overrides) and
  screenshot the room ~1s into the load wait — the LOADING-state
  QA capture. Disarms and quits right after the shot.

## Layout

```
core/   UI-independent: config, database, scanner, art, state, data,
        launch plan, watchdog contract, launch service
ui/     the faces: main routing, room, detail view, desk pass,
        texture factory (renders every text surface once, to texture),
        pointer rig, clickable quads, card specs
watchdog/  the native watchdog (Go): source + build.sh; exes are
        gitignored build artifacts
data/   bundled dummy vpsdb.json
dummy_data/  placeholder tables for the dummy flow
```

## Simplifications (honest list)

- Wall pages flip in blocks of 12 rather than a continuous drag-flip.
- One shared hover across both controllers (right hand preferred).
- The bundled database is invented; real-library match quality is a
  verdict item for Chris's machine.
- Ambiguous same-name db games (remakes) resolve to the first match;
  a correction UI is later work.
