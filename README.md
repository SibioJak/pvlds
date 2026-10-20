# PVLDS — Project VR Launcher That Doesn't Suck

A VR-first launcher for VPX (Visual Pinball) tables: put the headset on,
stand in front of your collection, pick a table, play. Built with
Godot 4.7 + OpenXR for PCVR (Quest 3 via Virtual Desktop / VDXR first;
SteamVR runtime is a later test target).

**Status: M1 — "The room."** Browsing, grouping, versions, favorites,
and the desk setup pass are in. **Play is a labeled stub** — launching
VPX, the watchdog, and the OpenXR hand-off are M2. Design of record:
`~/workspace/vpx-vr-launcher/design.md` (outside this repo).

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
  drive the whole UI flat at the desk (with a subtle parallax camera),
  which is how the room is judged without a headset.
- **First-run desk pass.** A flat 2D setup (never in-headset): point
  at the VPX executable (`VPinball_GL64.exe` expected) and the table
  folder(s), optionally a cached `vpsdb.json`. It writes a plain JSON
  config, runs the scan, and reports what the scan measured —
  duplicates, match rate, art coverage, unidentified titles.
- **State** (favorites, default builds, recents) persists as plain
  JSON in `user://pvlds_state.json`, ready for the M2 exit/relaunch
  cycle.
- **`.ini` files are sacred.** The launcher never reads, writes,
  moves, or regenerates table `.ini` files. Its own config lives next
  to the executable (or `user://` in editor runs), never in table
  folders; art extraction caches to `user://` too.

## Running it

- **Editor:** open the project in Godot 4.7 and F5. No config → the
  desk pass opens. Use its "Use the bundled dummy library" button to
  run the whole flow on invented tables.
- **Export:** the "Windows Desktop" preset writes `../builds/PVLDS.exe`
  relative to the project (i.e. `~/workspace/builds/`).

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
- `--setup` — force the desk pass even when a config exists.

## Layout

```
core/   UI-independent: config, database, scanner, art, state, data
ui/     the faces: main routing, room, detail view, desk pass,
        texture factory (renders every text surface once, to texture),
        pointer rig, clickable quads, card specs
data/   bundled dummy vpsdb.json
dummy_data/  placeholder tables for the dummy flow
```

## M1 simplifications (honest list)

- Wall pages flip in blocks of 12 rather than a continuous drag-flip.
- Recents records detail-view opens; from M2 it records launches.
- One shared hover across both controllers (right hand preferred).
- The bundled database is invented; real-library match quality is a
  verdict item for Chris's machine.
- Ambiguous same-name db games (remakes) resolve to the first match;
  a correction UI is later work.
