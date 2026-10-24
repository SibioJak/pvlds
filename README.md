# PVLDS — Project VR Launcher That Doesn't Suck

A VR-first launcher for VPX (Visual Pinball) tables: put the headset on,
stand in front of your collection, pick a table, play. Built with
Godot 4.7 + OpenXR for PCVR (Quest 3 via Virtual Desktop / VDXR first;
SteamVR runtime is a later test target).

**Status: M2 — "The hand-off" (built 2026-10-21; fix rounds
the same day, after the first real-hardware sessions — the
latest makes the room deaf during the load wait and makes every
disarm name its author, after the field logs caught sessions
being dismissed from under loading tables). A further round
(2026-10-22) swaps the exit gestures to Chris's mapping (tap
returns to the room, hold bails to the editor — the exit
arbitrator), adds the loading marquee, and fixes backglass
extraction for entity-escaped files (255 of his 281 backglasses
were stamped failed by the old reader). A third round the same
day fixes the gestures' silent failure on his rig — the player
sighting no longer demands the `VPPlayer` window class (his
player window never matched it, so neither duty ever armed;
`sighting.go`) — retunes the marquee smaller and farther back
(his verdict on the first pass: too big, too close), and gives
the focused card a hover pop-out off the wall. A fourth round
the same day strikes the hold gesture entirely, at Chris's
ruling ("I don't want any hold anything to do anything"):
D-pad right is now a plain BACK button with exactly two
meanings — in play it is VPX's own Exit Game and the watchdog
closes the editor it lands in, promptly and unconditionally;
in the room it quits the app to the desktop. The arbitrator,
the hold duty, the XInput button watch, and both exit switches
are gone. A fifth round (2026-10-23, after the tap-return
proved itself in the field) fixes the hand-off's two remaining
defects: the launcher now waits for the table's **runtime**
(the old cue — the window sighting — stamps off the editor's
canvas about a second after spawn, while a real load runs
several seconds more, leaving a desktop gap in the headset),
and the watchdog hands the foreground to the game **once** at
the hand-off, deliberately, ending the focus lottery that
left one table with sound and controls and the next with
neither until the player alt-tabbed to it. A sixth round the
same day adds the **activation sequence**: the hand-off push
works at process level and stood down in the field ("game
already holds the foreground") on a session where the pad and
the sound were dead anyway — because PinMAME's window held
the foreground and the game's SDL window, which owns input,
never did. After the runtime settles, the watchdog now puts
the foreground on the SDL window specifically, once,
verified (see "The activation sequence" below).** M1's room
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
- **The launcher stays for the load — and the room goes deaf for
  it.** On launch the launcher records state (recents, last-played,
  room view), writes the watchdog session contract in the
  **loading** state, spawns VPX detached — and **stays in the
  room**: the launched panel reads LOADING..., and **no control in
  the room answers input until the wait settles** — every quad is
  pick-disabled (EXIT and SETUP included), the focusable set is
  empty, the activation funnel refuses everything, and the banner
  says the controls are locked while the table loads. The wait's
  headline is the **loading marquee** (not a loading screen — no
  spinner, no progress bar): the wall of cards fades down and the
  launched table's year, with its designer beneath, flies in from
  the wall in big display letters and holds at reading distance
  with a gentle pulse until the wait settles (`room.gd`'s
  MARQUEE_* constants carry the tunables; fallbacks: manufacturer
  for a missing year, the title for a missing designer). First
  pass judged too big and too close in the headset; retuned the
  same day (year 170→110px, name 84→56px, settle depth
  −1.55→−2.30m). The wait is
  bounded (below), so no cancel control is offered. While
  browsing, the card on the room's shared focus — the pointer's
  card (VR laser / mouse hover) or the gamepad/keyboard focus's
  card — **pops out** toward the viewer (~0.15m, ~1.08×, ~150ms;
  `room.gd`'s POP_OUT_* constants), its Launch button riding the
  card face; focus loss settles it back flush. The deafness
  is a root-cause fix, not a nicety: the room listens to the same
  gamepad the player plays VPX with, and A is both "activate the
  focused quad" here and the player's plunger button there. An
  earlier build deliberately kept EXIT live during the wait with
  focus parked on it, so the player's first play press fired
  EXIT: the session disarmed silently, VPX finished loading
  detached, and the player later exited to an editor with no
  watchdog on duty — the "never returns to the interface" failure
  that survived five builds and every switch combination. A
  window close arriving during the wait is likewise logged and
  ignored (the environment — Virtual Desktop's session transfer
  is the known suspect — must not dismiss a session mid-handoff);
  outside the wait, a window close disarms and quits as before.
  The launcher exits at the hand-off, the first of: (a) the
  watchdog's contract reports the table's **runtime** exists
  (`runtime_seen_unix` — the runtime rule below), plus a ~1.5s
  settle; (b) the launcher's own XR session reports it is
  ending (VPX is taking the headset over); (c) a 45s hard cap,
  so the room can never hang on a stuck load. (The cue used to
  be the window sighting; it stamps seconds too early — see
  the runtime bullet under the watchdog.) As it exits it
  marks the session **live**. If VPX dies during the load instead,
  the session is marked **failed**, nobody relaunches anything,
  and the resident launcher flags the panel FAILED and returns to
  normal browsing (the rebuild restores every control exactly).
  After the hand-off the launcher is fully gone — no resident
  mode; absence remains the fix for the XR/focus fights.
- **Every disarm names its author.** `disarm()` takes a reason
  ("room Exit", "window close", the watchdog's own "watchdog loop
  cap", ...): the launcher prints `PVLDS DISARM: <reason>`, the
  reason rides the contract (`disarm_reason`, schema still v2 —
  absent in older contracts, read as empty), and the watchdog's
  stand-down log line quotes it (`contract disarmed (<reason>);
  standing down`, falling back to the legacy generic when empty).
  The silent disarm above is why: the log line that finally
  caught it could only say "player Exit", and which of its two
  possible authors fired in those historical sessions can no
  longer be proven — the reason field exists so the next
  occurrence, if any, confesses.
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
  **once**.
- **The runtime stamp and the one-shot focus handoff.** Alongside
  the sighting, the watchdog stamps `runtime_seen_unix` when the
  game's **table runtime** first exists (`runtime.go`): a window
  of the game process whose class is one of the runtime classes
  the field inventories showed arriving with the player and
  vanishing at the exit — PinMAME's `MAME` / `VPINMAMEEVENTWND`,
  the render windows `SharpGLRenderWindow` / `NVOpenGLPbuffer`,
  `DIEmWin`, the B2S server's `HwndWrapper…` windows — or an
  `SDL_app` window that is **visible** (in both field sessions
  it flipped hidden→visible exactly when the player came up).
  The editor's canvas (`CVFrame`), the editor class, and the
  dialog/IME crowd never count. This stamp — not the sighting —
  is the resident launcher's hand-off cue (above): the sighting
  stamps ~1s after spawn off the editor canvas while real loads
  run ~8s, and handing off on it left a 2–3s desktop gap in the
  headset. The sighting keeps its other jobs (the exit
  detector's arming precondition; the launcher's dead-process
  grace). At the hand-off moment itself — the first tick the
  session is live with the supervising launcher observed gone —
  the watchdog pushes the foreground to the game process
  **once**: target its visible SDL window, else its editor
  frame (same process — the push buys process focus), skipped
  if the game already holds the foreground, and logged either
  way (`handed focus to the game (one-shot)` / `game already
  holds the foreground` / `focus push declined by Windows`).
  Exactly once per session; it is not herding (herding stays
  loading-only and never runs live). Because the push can
  itself place the foreground on a non-editor game window, the
  exit detector's guard records the push tick: an excursion
  counts toward arming only if observed at a tick **after**
  the push — the push must never manufacture the detector's
  own arming evidence. The relaunched launcher restores filter/sort/page with
  the just-played table selected. It never auto-relaunches a
  table. A log lands beside the contract (`pvlds_watchdog.log`).
- **The activation sequence** (`activation.go`, decision logic
  shared and unit-tested on Linux): the fix for the field case
  the process-level push above cannot see. In session 35
  (Godzilla, watchdog-6 log) the push stood down — "game
  already holds the foreground" — and at process level it was
  right: the foreground cycled editor → loading dialog →
  `SDL_app` → `MAME`, all the game pid's own windows, and
  never left the process — while the table had no gamepad and
  no sound until the player alt-tabbed (his standing law: no
  controller ⇒ no sound; alt-tab cures both). The foreground's
  last internal move before play was PinMAME's `MAME` window
  taking it ~6s after the runtime came up; the game's
  `SDL_app` window — the one that owns input — never regained
  it. (In the good Getaway session it settled on `SDL_app`
  by itself.) So: per session, once the runtime has stamped
  and the session is live, the watchdog watches the
  foreground's identity (class + owner) until it has been
  unchanged for **2800ms** (`activationSettleMs`), or gives up
  waiting at runtime-up + **12s** (`activationDeadlineMs`) and
  resolves on whatever holds it then. Two patience rules ride
  on the settle, both from the watchdog-7 sessions (36–39,
  2026-10-23), where VPX's startup shuffle finished by ~+7s
  in every session but the bare settle rule could be fooled
  earlier: the sequence **may not resolve before runtime-up
  + 8s** (`activationResolveFloorMs`), and stability only
  accumulates under a real holder — the editor frame and the
  loading dialog are load-phase placeholders, and time on
  them is a **lull**, not a settle. Session 39 is the pinned
  failure: the foreground sat stable on the editor for the
  full settle constant mid-load, the sequence resolved at
  runtime +2s ("the editor holds the foreground; standing
  down") and went home — then VPX's real final moves landed
  (SDL at +3s, PinMAME's grab at +6s, held through dead
  play). In session 36 the foreground kept changing, the
  sequence stayed alive, caught PinMAME holding, pushed the
  SDL window, and the table worked. At resolution: if the
  foreground is already the SDL window, it logs `activation
  not needed` and stands down; if an eligible holder has it —
  any window of the game process, Virtual Desktop's window,
  or no window — it foregrounds the game's SDL window (the
  visible one if any, else any SDL window of the pid; **never
  the editor window, under any circumstances**), reads the
  foreground back ~1s later, retries once if it did not
  stick, and logs the outcome with the prior holder
  (`activation - foreground was "MAME"; set to the game's SDL
  window (stuck)` / `(did not stick after retry)`). Two
  refusals: the editor holding the foreground at resolution
  (that foreground belongs to the exit detector's story —
  during the settle it is only a lull and the sequence waits
  it out, but an editor grab with a push in flight aborts
  the sequence outright), and an unrelated third process
  holding it (never steal from a stranger). Exactly one sequence per
  session; nothing runs after it completes — it is **not**
  herding, and herding's loading-only gate is untouched. A
  push the sequence does make is recorded with the exit
  detector through the same `notePush` bookkeeping as the
  focus handoff, so the detector's excursion accounting is
  measured from facts after the watchdog's own last
  foreground touch.
- **Session-close duty** (Windows, user32; decision logic shared
  and unit-tested on Linux): in a **live** session, a table exit
  leaves VPX sitting in its editor with the process alive. The
  watchdog detects the landing by the **foreground** and closes
  VPX, orderly, so the return trip can finish. The detector
  (`closer.go`) arms per session on two facts together: the
  **sighting** has stamped (the table demonstrably loaded), and
  an **excursion** has been observed — at least one tick with
  the foreground somewhere other than the editor window (during
  load and play the foreground cycles Virtual Desktop's window,
  the loading dialog, the player, PinMAME; the editor holds it
  only at the spawn instant and when a table exit lands —
  field sessions 25/26, 2026-10-23). One guard rides on the
  excursion: it counts only if observed at a tick after the
  session's one-shot focus handoff (above) — the push can put
  the foreground on a game window itself, and the detector
  must never arm on evidence the watchdog manufactured. Once armed, the editor
  holding the foreground continuously for **1200ms**
  (`editorForegroundSustainMs` — elapsed time, not tick counts)
  is the exit; any tick with a different foreground resets the
  sustain clock. The detector replaced the older
  presence-drop trigger, retired because the window the
  sighting stamps off on Chris's rig turned out to be VPX's
  editor canvas, which persists through the editor state (see
  the field-findings bullet). The sighting rule (`sighting.go`)
  is unchanged and still supplies the stamp: the source names
  the player's SDL class as `VPPlayer` (`SDL_RegisterApp` in
  `src/core/VPApp.cpp`), and where a build uses it, it counts
  at once — but Chris's build's player window never carried
  that class across whole sessions of live play (the contract's
  `game_window_seen_unix` stayed 0, so neither close duty ever
  armed and both exit gestures were inert), so the rule is
  class-**independent**: any window of the game process —
  visible or hidden (see the next bullet) — that is NOT the
  editor class and is substantial (≥ ~320×240) counts once it
  persists across two polls; the editor class never counts, at
  any size, ever. The editor frame's class is **`VPinball`**
  (`WinEditor::PreRegisterClass` in `src/ui/win/WinEditor.cpp`);
  it is both the foreground identity and the WM_CLOSE target.
  The watchdog logs the game pid's full window inventory
  (class, size, and visibility of every window) when a
  session's set is first observed and again whenever it
  changes, naming the current foreground window each time, and
  names the rule that stamped the sighting — the field
  evidence the old rule never produced. Separately, in a
  **live** session the watchdog logs **every foreground
  identity change** (`session N: foreground changed:
  "OLDCLASS" (pid X) -> "NEWCLASS" (pid Y)`, `none` for no
  foreground window) — the inventory lines print only when
  the window *set* changes, and the set is static mid-play,
  so a mid-play foreground flicker used to leave no trace at
  all. That log is the input-loss forensics (2026-10-23:
  gamepad and keyboard dead in bursts mid-play while the
  table rendered fine): the next occurrence names its thief
  in the log, or acquits the foreground for good. Logging
  only — no decision reads it, and nothing behaves
  differently because it exists. A session that never
  leaves the editor can never fire the detector — no excursion,
  no arm (Chris's field case, 2026-10-22: VPX launched straight
  into its own editor, then closed from the editor; the first
  build without a sighting gate likewise closed VPX mid-load
  on slow tables, which the arming halves now exclude). Close
  method, in order: (1) the **PinSim::FrontEndControls**
  terminate request — the published protocol modern VP
  implements (registered window message, wParam 2 = CLOSE_APP,
  reply 1 = acknowledged; PinballY's `Application.cpp` is the
  reference sender); (2) **WM_CLOSE** to the editor window —
  which VP's own editor refuses while a player is open
  (`WinEditor::OnClose`), so it can only land in the state this
  duty targets. Never a hard kill; if neither lands, the
  watchdog logs it and leaves VPX alone. The duty is
  **unconditional** — there is no kill-switch and no desk
  checkbox for it (both were removed when the exit model was
  simplified; see the next bullet).
- **Field findings the current code is shaped by** (from
  Chris's rig logs): **the player window is not a desktop
  window at all** (2026-10-22) — under Virtual Desktop the
  GL64 player renders into the headset, so the watchdog's
  window inventory listed exactly one window for the game
  process across whole sessions (the editor, 1167×634), and
  every window fact that filtered on visibility (the old
  enumeration skipped `IsWindowVisible == 0`) starved the
  sighting even after the class rule was fixed; the sighting
  now enumerates ALL of the game pid's top-level windows,
  visibility recorded but ignored, while herding keeps the
  visible-only set its anchor needs. **A relaunched room can
  be born with the button already down** (2026-10-22): after
  Chris closed the editor by hand, the death → relaunch trip
  worked — and the fresh room then quit to the desktop
  uncommanded, its log ending in a "room Exit" disarm, because
  its controller reconnected mid-relaunch and D-pad right read
  pressed as the new instance polled. So the room's D-pad exit
  is baseline-armed: it fires only on a press edge that occurs
  after that room instance has observed the button released at
  least once; a button pressed from the instance's first poll
  can never fire it, however long it sits. **The sighting's
  window is the editor's canvas, not the player** (2026-10-23,
  sessions 25/26): once the enumeration went unfiltered, the
  sighting began stamping reliably — off a hidden `CVFrame`
  window, 1401×809 — but that window **persists in the editor
  state after a table exits**: `CVFrame` is VPX's editor
  canvas, so player-presence never drops and the closer's old
  presence-drop trigger could never fire. (The windows that DO
  vanish on exit belong to PinMAME and B2S, not the player.)
  The same sessions showed the signal that IS clean: the
  foreground is never the editor during load or play, and is
  exactly the editor the moment a table exit lands — hence
  the foreground exit detector above, and hence herding being
  confined to the loading phase: its anchor is the editor
  frame (the only visible window), and in session 26 it
  actively forced the editor to the foreground mid-play,
  polluting the very signal the detector reads.
  **The hand-off's two defects** (2026-10-23, the first field
  session where the tap-return worked end to end): the room
  left on the sighting cue ~1s after spawn while the table
  took ~8s to load — a 2–3s desktop gap in the headset and an
  unsettled foreground — and focus at the hand-off was a
  lottery between tables: The Getaway won it (sound +
  controls from the first moment), Godzilla lost it (no
  sound, no controller) until Chris alt-tabbed to the game,
  which cured both instantly — the game had simply never held
  Windows focus. Hence the runtime cue and the one-shot focus
  handoff above: the room stays until the table is real, and
  the foreground is given deliberately, once.
- **The exit model — one BACK button, two rules** (Chris's
  ruling, 2026-10-22, replacing the tap/hold arbitration model
  wholesale): **there is no hold gesture anywhere.** D-pad
  right — Chris's recorded VPX ExitGame binding ("right
  directional") — is a plain BACK button. **Playing a table:**
  a tap is VPX's own business and lands in the VPX editor, as
  it always has; the watchdog's session-close duty (above)
  then closes VPX once the exit detector confirms the landing
  — the editor holding the foreground for the 1200ms sustain —
  and the ordinary death → relaunch flow brings the room back.
  The editor is never a resting place. **On the table select
  screen (the room):** a fresh D-pad right press quits the app
  altogether to the desktop — the rail EXIT action (disarm
  "room Exit" + quit) on the pad, in browsing and in the
  detail view. D-pad up/down/left and the left stick still
  move focus (the stick moves it rightward too); during the
  load wait the room stays deaf and swallows the press like
  everything else, and on the SETUP placard it does nothing —
  BACK remains the only way off the placard. Neither side
  reads the button for the other: PVLDS never sees the
  in-play press at all (the watchdog no longer contains a
  gamepad watch of any kind), and the room's press is an
  ordinary edge-triggered poll of the pad it already reads
  for focus. The stricken machinery — `arbiter.go`, the hold
  duty, the press tracker, the XInput watch, and the
  `close_vpx_on_table_exit` / `hold_exit_enabled` /
  `hold_exit_button` settings on the desk, in the config, and
  in the contract — is deleted, not disabled; contracts and
  configs written by older builds still load (both readers
  ignore the dead keys, and fresh writes stop emitting them).
- **Focus herding** (Windows, user32): while a session is
  **loading** — the spawn-settle phase it was built for — if
  the foreground leaves the game process and stays away past a
  2s grace period, the watchdog hands foreground back to the
  game's main window (rate-limited; it never moves or resizes
  windows). It **never runs once the session is live**: on
  Chris's VR rig its only anchor there is the editor frame,
  and it was caught forcing the editor to the foreground
  mid-play (field session 26, 2026-10-23) — the exact signal
  the exit detector reads. The gate is the shared, unit-tested
  `herdingAllowed` (`herd_logic.go`). **It yields to
  deliberate use**: if the same foreign window is back in
  front after 3 re-assertions against it, herding stands down
  for the rest of that session and logs it — a player working
  at the desktop (say, clearing an error dialog) is never
  fought. The decision logic is shared and unit-tested on
  Linux; the next session starts fresh. Kill-switch: the
  **Focus herding** checkbox on the desk pass (config
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
- **Scans never block the UI, and art warms in the background.**
  The scan (db load + folder walk + matching) runs on a
  WorkerThreadPool task with live progress in both routes that
  trigger it (desk Save & Scan, and the configured auto-boot, which
  presents the desk as a shell and enters the room when results
  land). Extracting a backglass from a `.directb2s` costs ~200 ms
  per file at real-world sizes, so the scan records only
  directory-listing facts (a same-stem image or `.directb2s`
  exists) — then `ArtWarmer` pre-extracts the whole library on a
  background worker into `user://art_cache`, neighbouring pages
  first as they are browsed to. Cache entries are stamped by the
  source's size + modified time (a replaced backglass invalidates
  its entry) and stored at panel size (fit inside 512x640), so a
  warm panel is a small file read. A panel that reaches an unwarmed
  game first extracts it itself via `GameEntry.ensure_art()`; a
  claim registry guarantees the warmer and a panel never extract
  the same file twice, and a panel never queues behind the
  warmer's list. Every extraction's outcome is recorded in an
  index beside the cache (`art_index.json`, same stamp): **ok**,
  **no image in file**, or **failed** (unreadable/undecodable).
  A stamped negative is remembered — panels render the title card
  immediately and the warmer never re-queues the file until it
  changes, so a no-art table costs nothing on later visits. Each
  entry also carries the extractor's format version: entries from
  an older extractor count as untried and are retried once under
  the current one — v2's retry is what recovered the library's
  entity-escaped backglasses (designer files that wrap the
  base64 at 76 chars and store each wrap's CRLF in the attribute
  as `&#xD;&#xA;`, which v1's strict decoder refused whole: 255
  of 281 backglasses on Chris's library; the reader now
  XML-unescapes attribute values before decoding); a
  panel whose claim on the warmer's in-flight extraction stalls
  past ~3s extracts the file itself rather than waiting. The
  extractor targets the format as the B2S server (the reference
  reader) defines it — `Images/BackglassImage`'s `Value`
  attribute first, then the on/off pair, the DMD image, then the
  largest image blob anywhere — and decodes PNG/JPEG/BMP/WebP/TGA
  from UTF-8 or UTF-16LE files. The desk summary reports the
  index's exact ok / no-image / failed / untried counts for the
  library. (History: the original eager, main-thread scan
  froze the app for over a minute at 300 tables, 2026-10-20; the
  lazy-only fix that followed moved the cost onto first page
  visits, which is what the warmer retired, 2026-10-21.)
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
- **The missing-backglass list.** Every completed scan also
  regenerates `missing_b2s.txt` in the app data folder (`user://`,
  beside the state file and the watchdog contract): a short header
  (scan date, missing count), then one line per `.vpx` file that
  has no same-stem `.directb2s` beside it — file name plus the
  folder it lives in, alphabetical by file name. The record comes
  from the scanner's own pairing pass (a side image does not clear
  a file; this is about the backglass file itself, per file, so a
  multi-build game can be listed for one build and not another).
  The desk shows the count beside the scan summary, with an
  **Open list** button that hands the file to the OS's default
  text handler. It is the go-download shopping list: drop the
  matching backglasses into their folders, rescan, and the
  entries clear.
- **SETUP never strands the headset.** The desk is a 2D form and
  cannot render into the headset — so while XR is live, opening
  setup (rail SETUP, or a failed launch routing to the desk) no
  longer hides the room (that blacked out the player's view with
  no way back — field fault, 2026-10-21). The desk still opens on
  the monitor; in the room a placard stands instead — "Setup is
  open on your desktop," any failure message riding on it, and a
  BACK control. While it stands, every other room control is
  inert; BACK (or Enter the Room on the desk) closes the desk and
  hands the room back.
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
- `--pvlds-art-bench` — with an installed config: boot into the
  room, print ARTBENCH timings (cold first page, cold deep-page
  flip, full-library warm duration, warm flip, worst frame costs),
  quit. The art-speed measurement harness (needs a real rendering
  driver, like `--pvlds-shot`).
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
  QA capture. Disarms and quits right after the shot. The capture
  delay is retunable via `PVLDS_SHOT_LAUNCH_DELAY_MS` (the
  marquee QA loop shoots mid-fly-in and settled frames).
- `--pvlds-smoke-placard` — room boot; force the XR flag on, open
  setup with a message, and assert the placard contract (room
  stays up, placard stands with the message, wall/rail inert,
  focus confined to BACK), then BACK restores the room and closes
  the desk; a second leg with the flag off asserts the flat path
  is the legacy one. Prints ok/FAIL lines, exits 0/1.
- `--pvlds-smoke-desk` — desk boot (the flag keeps the boot on
  the desk: no scan, no room); flip the desk's session switch
  (focus herding — the only one left) through its real signal
  and assert the config FILE on disk changed with no Save &
  Scan; also assert the stricken Close VPX / Hold-to-exit
  controls are absent from the desk and that the saved config
  carries none of the stricken keys. Prints ok/FAIL lines,
  exits 0/1.
- `--pvlds-smoke-dpadexit` — room boot; inject a synthetic
  fresh D-pad Right press into the room's real gamepad poll.
  The app must exit through the rail EXIT path before the
  driver can complain (disarm "room Exit" + quit); the harness
  (`run_dpadexit_smoke.sh`) asserts exit code 0 and the disarm
  + reason on the contract from outside. Sibling flag
  `--pvlds-smoke-dpadexit-held` is the baseline-arming leg:
  the button is pinned pressed from boot, before the room
  instance's first poll — the app must survive it pinned,
  then exit on a fresh press after the driver's release.
- `--pvlds-smoke-quitwarm` — desk boot; the exit-hang harness
  driver (`~/workspace/pvlds-harness/run_quitwarm_smoke.sh`).
  Exits mid-warm-pass through the real rail path; mode "drain"
  (env `PVLDS_QUITWARM_MODE=drain`) lets the warm finish first.
  Every app quit now stops the art warmer's pass at its next
  item boundary (`ArtWarmer.request_stop`, called on the rail
  Exit, window-close, and launch hand-off paths, with a
  NOTIFICATION_EXIT_TREE backstop) — an unstopped pass made
  quit wait out the whole queue.

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
