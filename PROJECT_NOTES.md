# Obsessed — Project Notes

Handoff/reference doc for the game. If you're an AI assistant starting a fresh
chat on this project, read this first, then read the files referenced below to
get the exact current values.

## What this game is
An atmospheric, low-poly, found-footage horror game (Outlast-style camcorder).
The player explores a dark, abandoned hospital holding a camcorder. An entity
stalks the player but is **only visible through the camcorder screen**, and it
runs out of sight when filmed.

- Engine: **Godot 4.7** (Forward+, Jolt physics, D3D12 on Windows).
- Main scene: `main.tscn` (project main scene, referenced **by path** in
  project.godot — not by uid, because the file gets regenerated).
- Current art state: **textured blockout** (July 2026). Rooms still empty (no
  props). Materials are built in `_make_materials()` in `build_map.gd`:
  - Walls = worn mossy plaster, floors = worn tile, ceilings/roof = granite
    tile — three PolyHaven-style 4K PBR sets (diff jpg + nor_gl exr + rough
    exr) in `assets/*_4k.blend/textures/`, applied with **world triplanar**
    (no UVs needed, pattern lines up across boxes). `uv1_scale` = repeats/m.
  - Grass / concrete (stairs, counters) / wood (planks, trim) come from the
    stylised `assets/ld_textures_*.png` pack, tinted via albedo_color.
    (Pink/magenta ld files are tint-template variants — use the coloured ones.)
  - Door leaves use plain UV wood (NOT world triplanar — they move).
  - **No ceiling bleed**: each mid-slab piece is tile (floor 2's floor) with a
    thin granite "Ceil" panel glued underneath (floor 1's ceiling) — see
    `slab()`. The roof is granite, so its underside is floor 2's ceiling.
- **Courtyard** (July 2026): open-air shaft at x 14..24, z −4..3 — grass
  patch on the ground, holes in the mid-slab and roof above it, blue
  "CourtyardLight" moon pool. Two floor-1 doors in (x 19 on the z=−4 and z=3
  walls); the matching floor-2 doors were removed so nobody steps into the pit.

## Controls
- **WASD** — move (slow walk), **Left Shift** — sprint (stamina bar)
- **Mouse** — look, **Space** — jump
- **1** — hold the flashlight, **2** — hold the camcorder (`select_flashlight`
  / `select_camera`, pure item selects — pressing the key of the item already
  in hand does nothing). Always exactly one item in hand.
- **Right mouse** — raise/lower the camcorder (`toggle_record`), and ONLY
  this raises it. Ignored while the flashlight is held. Raised = the entity
  gets pushed away. **Drains battery.**
- **E** — open/close doors, collect pages/batteries (`interact`)
- **Esc** — pause menu (resume / options / main menu / quit). The mouse is
  freed while paused and recaptured on resume (`player.gd _notification`).

## THE MAP IS GENERATED — do not hand-edit main.tscn
`main.tscn` (~2000 nodes) is written by **`scripts/build_map.gd`**. To change
the map, edit the layout data in that script and run **`tools/builder.tscn`**
once (e.g. via the Godot MCP: run scene `res://tools/builder.tscn`). It
rebuilds everything, saves `main.tscn`, prints `MAP BUILD DONE`, and quits.
This guarantees aligned walls/stairs with no clipping. Player and Entity
instances, environment, lights and nav links are all created by the builder.

## Level layout — modelled on a real hospital floor plan (2 floors)
Coordinates: North = **-Z** (top of the blueprint drawing). Building is
**110 m (X -55..55) × 75 m (Z -37.5..37.5)**. Floor 1 walls y 0..4, mid slab
y 3.9..4.1, floor 2 walls y 4.1..8.1, roof above.

**Corridor grid (same on both floors, so the building hangs together):**
- 4 east-west corridors: z −28..−25 (front), z −14..−11 (main spine),
  z 3..6, z 20..23 (south).
- 4 north-south corridors: V1 x −38..−35, V2 x −1.5..1.5, V3 x 32..35,
  V4 x 44..47 (ER corridor).

**Floor 1 (from the blueprint), north band west→east:** Dining Room, Gift
Shop, Restrooms, **Lobby** (player spawn; boarded main entrance + vestibule
with working double doors, reception counter), Chapel, Waiting Area, ER
Registration, ER Waiting (boarded ER entrance on the east perimeter, boarded
patient entrance NE). **Middle:** Serving Area, offices, Main Patient
Registration (counter, double door onto the spine corridor), Ultrasound, Lab,
EKG, **central stairwell + dead elevators**, X-Ray, Dark Room, Nuclear
Medicine, Physician Dining, ER Fast Track, ER bay. **South:** MRI (big, double
door), MRI control + hot lab, wards, **ER rooms 10–15** in a row on the east
edge (doors off V4), Morgue, Central Stores, Boiler, Laundry, **SW stairwell +
dead elevators**, Ambulance Bay (boarded roll door; **entity spawn**).

**Floor 2 (invented ward floor):** patient rooms along the whole north and
south edges, Nurse Station (two counters) mid-north, Day Room, Treatment,
Operating Theatres 1–2 + Scrub/Sterile above imaging, Pharmacy, ICU (east open
bay), Physio hall above the MRI, iso wards on the east edge.

**Stairwells (2, both switchback/U-turn, raw stepped geometry):**
- Central: interior x 1.5..7.5, z −11..−4. SW: x −53..−47, z 23..30.
- Entry door AND upstairs exit both on the north wall, so both floors connect
  to the same corridor. Flight A (west) 10 steps up to a half-landing, flight
  B (east) 10 steps back north, total rise 4.1 = exactly the slab top.
- Step: rise 0.205, going 0.3, width 2.4. Spine wall between flights, railing
  upstairs along the stair hole. **Two `NavigationLink3D`s per stairwell**
  (July 2026), each laid exactly along its ramp line (StairLinkA/B) — the old
  single diagonal link made the entity fly/clip across the shaft.
- **Steps are visual-only** (July 2026): collision comes from invisible
  `StairRamp` boxes (one per flight, `ramp()` in `build_map.gd`) whose top
  surface runs along the step nose line — the player glides up smoothly, and
  the navmesh bakes on the ramps so the entity glides too. The half-landing
  is 1.7 deep so it also covers the top step of each flight.
- Dead elevator banks (sealed dark panels) sit beside each stairwell, matching
  the blueprint's elevator positions.

**Spawns:** Player (−11, 0.3, −33.8) in the lobby facing south. Entity
(48, 0.1, 30) in the ambulance bay — far corner of the map.

## Working doors (~90 of them)
- Scene shape: `Door` hinge Node3D (script `scripts/door.gd`, group "door") →
  `Panel` StaticBody3D on **collision layer 2**.
- Player presses **E** → `player.gd _try_interact()` raycasts 2.4 m from the
  camera; if the hit's parent has `toggle()`, it's called. Player
  `collision_mask = 3` so closed doors block them.
- The **entity ignores door collision entirely**: the navmesh bakes with
  `geometry_collision_mask = 1`, so layer-2 panels never cut the navmesh.
  Instead, `door.gd` watches for the entity (group "entity") within 2.2 m and
  **slams the door open** (0.12 s tween) — it shoves doors, never blocked.
  The slam is guaranteed audible to 20 m (max_distance 20, unit_size 10),
  so the player always hears the entity coming through doors.
- Double doors = two hinges, second one flipped with a mirrored angle.
- **Swings are RELATIVE to the hinge's starting rotation** (July 2026 fix):
  hinges spawn pre-rotated (v-wall doors −90°, flipped leaves +180°), so
  `door.gd` stores `closed_y`/`closed_facing` in _ready and tweens to
  closed_y ± open_angle. Tweening to absolute angles made those doors spin
  into the wall. One tween at a time (old one killed), and the slam won't
  re-fire while already swinging to the same spot.
- Doorways have headers (wall above y 2.2), so they read as real door frames.
- **Door frames + flush leaves (July 2026)**: every doorway gets dark trim —
  two jambs + a lintel (`_frame()` in `build_map.gd`, `mat_frame`), standing
  slightly proud of the wall. **Frames are VISUAL-ONLY** (no collision):
  solid frames pinched every doorway on the navmesh and the entity couldn't
  path through. The nav agent is also slimmed to exact voxel sizes
  (agent_height 1.5, agent_radius 0.25) so doorways bake comfortably open. Leaves are sized to the opening with even 2 cm
  clearances (single leaf = gap−0.16, double leaf = gap/2−0.09), 2.11 m tall
  under the lintel, and each has a small dark handle (visual only).
- **Doors swing INTO rooms, away from corridors** (July 2026): `_swing_side()`
  in `build_map.gd` checks the corridor bands and picks the door's open side,
  so open doors never stick out into a corridor. Room-to-room doors keep the
  old default side.
- The entity's slam now swings the door **away from whichever side the entity
  is on**, and also re-slams doors left open toward it — so a door can never
  end up across its path.
- The entity no longer picks "behind an open door" as a hiding spot
  (`_choose_evade` rays use collision mask 1 = walls only).

## File map
- `main.tscn` — the level. GENERATED, see above.
- `scripts/build_map.gd` — the map generator (all layout data lives here).
- `tools/builder.tscn` — run this scene to regenerate main.tscn.
- `scripts/door.gd` — working door (player toggle + entity shove).
- `scripts/page_manager.gd` / `scripts/page.gd` — collectible pages + win.
- `scenes/player.tscn` / `scripts/player.gd` — first-person player
  (group "player", collision_mask 3, step-up climbing, stamina HUD, interact).
- `scenes/entity.tscn` / `scripts/entity.gd` — the stalker (group "entity",
  Node3D + NavigationAgent3D, no physics body).
- `scripts/camcorder.gd`, `shaders/lcd.gdshader` — camcorder feed + VHS look.
- `shaders/retro_post.gdshader` — full-screen fog/noise/color-crush/dither for
  the MAIN view only (user-supplied). Lives on the `RetroPost` fullscreen quad
  under `Head/Camera3D` in `player.tscn`, render layer 2 so the feed camera
  culls it. Tune via its shader params on that node.
- `scripts/nav_baker.gd` — on the Nav region, bakes the navmesh at runtime.
- `scripts/spiral_stairs.gd`, `scripts/straight_stairs.gd`,
  `shaders/vhs.gdshader`, `assets/jejungwon_hospital.glb` — OLD/unused.

## Camera battery + flashlight (July 2026)
- **Battery** (`camcorder.gd`): filming drains it (`battery_max` = 40 s of
  footage). At 0 the camera dies INSTANTLY — screen black, auto-lowers,
  won't raise (dead clunk) until a battery is found. HUD: green bar above
  stamina (blinks when < 20%, `_update_battery_hud` in player.gd) + BATT %
  on the LCD (goes red when low).
- **Battery pickups**: 6 per run, spawned by `page_manager.gd` from the same
  SPOTS list pages use (floor position, never at a page's spot; E to grab =
  FULL refill, "BATTERY REPLACED" flash, `scripts/battery.gd`).
- **Flashlight is a real handheld item**: "FlashlightRig" under Head/Camera3D
  in player.tscn (torch model on render layer 2 + "Spot" SpotLight3D, 20 m,
  32°, warm, shadows). Key **1** pulls it out, key **2** / right mouse the
  camera — swapping is a full item switch: the camcorder animates to a
  `stowed_position` fully out of frame and the torch comes up (all poses are
  exports on camcorder.gd; the beam fades with `flash_amount`). Flashlight
  costs nothing. Keys are PURE selects (July 2026): 1/2 only swap items,
  right click only raises/lowers the held camcorder (`_select_flashlight` /
  `_select_camera` / `_toggle_record` in camcorder.gd).
- **Raised camcorder pose is the original dead-on one** (an angled version
  was tried and rejected). The body hides the screen's far right edge, so
  the BATT readout sits on the LEFT of the feed, under REC (BattLabel in
  player.tscn). Pressing 2 while holding the flashlight only swaps back to
  CARRYING the camera — a second press raises it.
- **LCD screen is dead glass unless engaged**: `screen_on` uniform in
  `lcd.gdshader`, driven every frame from camcorder.gd (raise amount, forced
  0 with an empty battery).
- **Darker world** (the flashlight/camera are how you see): environment in
  `build_map.gd` — ambient 0.05, lamps 0.16, moon 0.04. **All fog is BLACK
  (July 2026)** so distance reads as darkness, not grey haze: env
  fog_light_color (0.008,0.008,0.01) and retro_post fog_color
  (0.004,0.004,0.006) + very dark noise_color, fog_distance 12 / fade 10
  (player.tscn). The FEED gets its own material (`ShaderMaterial_retro_feed`,
  fog_distance 26 + brightness 1.15) so the camcorder genuinely sees further
  in the dark than the naked eye. Torch beam: LIGHT_ENERGY 14 in
  camcorder.gd, range 36 / 35° on the Spot node; main-view retro fog opened
  to fog_distance 17 / fade 14 so the beam actually reveals the distance.
- **Corridor ceiling fixtures (July 2026)**: `ceiling_light()` in
  build_map.gd puts a visible fluorescent fixture (dark housing + tube) at
  every corridor light spot on both floors (EW rows + rotated NS ones).
  Random state per BUILD (`_light_state()`): ~62% dead (pale tube, no
  light), ~23% dim steady (energy 0.55, range 8), ~15% flickering —
  `scripts/flicker_light.gd` blinks the OmniLight + its own copy of the
  tube material, and hums (buzz_loop 3D). Room lamps are still bare
  `lamp()` OmniLights.

## The camera-feed trick (core of the look)
The VHS effect is only on the camcorder's flip-out LCD:
1. `CameraFeed/FeedCamera` (Camera3D in a SubViewport) renders the forward
   view to a 512×320 texture; `camcorder.gd` copies the main camera transform
   every frame, FOV 55°.
2. The texture shows on the `FlipScreen` quad with `lcd.gdshader` (VHS +
   night vision + backlight glow).
3. REC/BATT/timestamp UI lives inside the SubViewport, part of the footage.
4. `camcorder.gd._ready()` wires the texture into the shader at runtime.

## Render layers ("only visible on camera")
- Layer 1: level geometry (both cameras). Layer 2 (render): camcorder model
  (main camera only). Layer 3 (`layers = 4`): the ENTITY (feed camera only,
  `cast_shadow = 0`).
- Main camera `cull_mask = 1048571`, feed camera `cull_mask = 1048573`.
- New entity parts → `layers = 4` + no shadow. New camcorder parts → `layers = 2`.
- (Don't confuse RENDER layers with the door COLLISION layer 2.)

## Entity AI (`scripts/entity.gd`) — stalker rework (July 2026)
- **STALK**: walks toward the player at player walk speed (3.0), but stops and
  lurks ~14 m away, staring. The lurk ring shrinks 0.15 m/s (down to 9 m)
  while unfilmed, so it eventually creeps into chase range on its own.
- **CHASE**: within 10 m (`chase_trigger`) it sprints at the player at 6.0;
  within 2 m (`lunge_distance`) it lunges at 8.0. Backs off to STALK if the
  player gets >14 m away.
- **CATCH / JUMPSCARE (July 2026, screen-space)**: within 1 m
  (`catch_distance`, not while FLEEing) → `_catch_player()`, all in ONE
  frame: player frozen (physics + input off), and the model is REPARENTED
  out of the level into an empty SubViewport world (`own_world_3d`,
  640×360 = grainy) with its own camera 0.38 m in front of the head bone
  (fov 33, judders ±2.5 every frame) + a hard OmniLight. That texture is
  pasted fullscreen (TextureRect), so the face fills the screen with ZERO
  wall clipping (an earlier version teleported the model in-world - it
  clipped, don't go back). VHS static overlay on top
  (`shaders/scare_static.gdshader`, intensity flickered with random
  white-out bursts), `jumpscare.res` scream non-3D and loud, jaw 1.1 wide +
  violent shaking for 1.1 s → hard cut to black, "it got you.", main menu
  ~2.8 s later. Tunables: SCARE_FOV, SCARE_CAM_DIST, timings in
  `_scare_tick`.
  `_scare_tick()` rattles it (jaw 1.1 wide, head shaking) for 1.1 s, then
  hard cut to black + "it got you." and back to the main menu ~2.8 s later.
- **FLEE**: filmed → panics, sprints to cover at 6.0 (2x player walk).
  **Anti-freeze (July 2026)**: evade spots < 2 m away are rejected (running
  "to where it stands" froze it on the stairs), agent
  `target_desired_distance` is 0.25 so it truly reaches cover, and a
  watchdog (`flee_stuck`) repicks faster with a widening search ring
  (spread up to 3x) whenever it stands frozen in full view; last resort =
  bolt straight away from the player.
- **TELEPORT**: once FULLY hidden from the camera for 0.3 s (all 3 rays —
  feet/chest/head — blocked, OR camera lowered), it teleports to a navmesh
  point 35–55 m from the player (prefers spots the camera can't see).
  Candidates are rejected unless `_spot_has_room()` passes (2 m headroom ray
  + 4 chest-height 0.5 m rays, mask 1) — no clipping into walls/ceilings.
  **Can't land outside (July 2026, two layers):** `nav_baker.gd` bakes with a
  `filter_baking_aabb` (y < 6.5, xz inside the walls) so no navmesh exists on
  the roof top or the ground rim outside; and `_inside_building()` in
  entity.gd rejects any teleport/evade candidate with y > 4.5 or past the
  walls as a safety net.
- **After teleporting: 20 s calm, THEN relentless** (July 2026): it lands in
  STALK with `cooldown = teleport_cooldown` (20 s) during which it cannot
  start a chase. When the cooldown runs out, `relentless = true` kicks in:
  CHASE from anywhere, `chase_exit` ignored, until FILMED again (filming
  clears the flag → FLEE loop).
- **Rage scaling** (July 2026): `set_rage(pages)` (called by page_manager on
  each pickup) sets `rage_mult = 1.0 + 0.1 × pages` (cap 1.5). Multiplies
  walk/chase/lunge speeds, `chase_trigger`, and `creep_rate`. Flee speed
  untouched.
- **Ducks under doorways** (July 2026): `_low_overhead()` rays up (2.4 m,
  mask 1) at its feet and 1 m ahead; anything low overhead (doorway headers
  at 2.2) blends `duck` 0→1 — hips drop 0.45, spine folds harder, head still
  staring — so it visibly squeezes through door frames.
- "Filmed" = camera raised AND (in ~45° cone with any body part visible, or
  within 3 m point-blank).
- **Real model (July 2026)**: `assets/smily_horror_monster.glb` (user-
  supplied, Sketchfab). Loaded AT RUNTIME in `_load_model()` with
  GLTFDocument (no editor import needed). The raw file is ~118 m tall —
  scaled to `model_height` (2.2 m), feet offset baked in, wrapped in a
  "Model" Node3D. **Facing is AUTO-DETECTED** (July 2026): the toe−foot
  direction of both feet (rest pose, averaged) says which way the mesh
  fronts; the wrapper is turned so that lines up with -Z (`face_yaw`, also
  used to aim the jumpscare camera). `model_yaw` export = extra manual
  degrees on top (default 0) if the auto answer is ever off.
  All meshes forced to render layer 3 + no shadow. Its single baked
  animation is ignored; `_pose_model()` poses the skeleton bones directly
  (bone name map in `_load_model`). The old box rig stays in entity.tscn as
  an invisible fallback (shown again only if the model fails to load).
  `tools/model_probe.tscn` prints any glb's tree/bones/animations/size.
- Animation is code-driven and twitchy: hunched spine, head tilted/staring,
  uneven limping gait, random head/spine jerks, whole-body shiver — all far
  more violent while FLEEing (the camera "hurts" it). On the model this
  runs on real bones (belly+chest curve, neck/head stare, jaw gapes open
  while chasing/panicking, limping legs, dangling arms).
- **Movement is straight-line 3D** (July 2026): `_navigate_to` walks directly
  along the line to the next path point (no more "move flat, fix height
  separately"), so on the ramp-aligned stair links it glides up/down the
  slope exactly like the player — no slab clipping. The per-flight
  `NavigationLink3D`s guarantee floor-to-floor pathing even if the baked
  navmesh over the ramps has seams.

## Pages — the win condition (July 2026, Slender-style)
- **Goal: collect all 5 pages pinned to walls.** Random spots each run.
- `scripts/page_manager.gd` — node "PageManager" in main.tscn (added by the
  builder). Holds a `SPOTS` list of ~20 hand-placed wall spots ([position,
  facing degrees]; page height 1.5 floor 1 / 5.6 floor 2). On _ready it
  shuffles, picks 5 that are ≥18 m apart (`MIN_SPACING`), and builds each
  page in code (white sheet + ink scribbles, faint emission so it's visible
  in the dark, collision layer 2 so the navmesh ignores it). All spots are
  on corridor walls or in rooms with a verified way in — always reachable.
  **Add/move spots by editing SPOTS — no map rebuild needed.**
- Spawn hardening (July 2026): spawning waits one physics frame, `_spot_ok()`
  raycasts out of each page's face (mask 1) and skips wall-buried spots
  (push_warning), each spawn prints `PAGE X spawned at ...` to the console,
  and a push_error fires if fewer than 5 spawn — check the log if a page
  ever seems missing.
- Each pickup calls `set_rage(found)` on the entity (aggression scaling).
- `scripts/page.gd` — on each page body; `collect()` emits "collected".
- Pickup: player E-ray (`_try_interact`) now checks `collect()` on the hit
  body BEFORE the door `toggle()` check.
- On pickup: `page_pickup.res` plays (paper crinkle + deep Slender boom,
  baked in `audio_baker.gd`) and a "PAGE X/5" HUD label fades in/out.
- **Page counter (July 2026)**: 5 small paper icons top-left, always
  visible — dim outlines that fill in (paper + scribbles, brief white
  flash) as pages are collected. Drawn by the `PageIcon` inner class in
  `page_manager.gd` (custom `_draw`), built in `_build_hud()`.
- All 5 → fade to black, "you escaped." text, pause, then back to the main
  menu after ~3.5 s (tween uses TWEEN_PAUSE_PROCESS so it runs while paused).

## Sound (July 2026) — mix of real recordings + synthesized
- **Real recordings** (freesound files in `audio/real audio/`) are cut into
  game-ready `.res` files by `scripts/real_audio_baker.gd` — run
  `tools/real_audio_baker.tscn` once, prints `REAL AUDIO BAKE DONE`.
  It makes: `step_player_1..3` + `step_entity_1..3` (single steps sliced out
  of the long factory-hall recording; entity ones slowed 1.4x = heavier),
  `breath_1/2` (calm), `breath_sprint_1/2` (gasping, used when stress > 0.55),
  `creak_1/2` (door creak; #2 slowed 15%), `roar.res` (ogg saved directly —
  plays once when filming scares the entity away, replaced the old synth
  scream loop; entity footsteps now keep playing while it flees), and
  `jumpscare.res` (monster death scream, RESERVED for the catch/game-over
  reaction — not wired in yet).
- **Everything else is still synthesized by `scripts/audio_baker.gd`**
  (`tools/audio_baker.tscn`, prints `AUDIO BAKE DONE`): heartbeat, cam whir,
  ambience loops/one-shots, door slam, page pickup. **If you re-run it, run
  the real baker again afterwards** — it overwrites the same file names.
- **Entity** (`entity.gd`): 3D footsteps synced to the stride animation
  (audible ≤30 m, louder in CHASE, faster when sprinting — free, since steps
  fire off `walk_phase`). While FLEEing (filmed) the footsteps are replaced by
  a looping scream (carries 60 m). `flee_speed` raised 6 → 8. New helper
  `is_chasing()` for the player's heartbeat.
- **Player** (`player.gd`, `_update_audio`): footsteps every stride (1.7 m
  walk / 2.0 m sprint); breathing always ticking faintly, ramps up with
  `stress = max(tired, entity within 15 m)`; heartbeat while the entity
  chases, 85→160 bpm the closer it gets, slow fade-out after escape.
- **Camcorder** (`camcorder.gd`): rising motor whir on raise, falling whir +
  clunk on lower (`cam_up.res` / `cam_down.res`). Same sounds pitched up 1.6
  = the flashlight click; pitched down 0.8 = the dead-battery clunk.
- **Industrial hum** (`ambience.gd`): `industrial_loop.res` (real recording)
  plays constantly at −16 dB, but randomly dies (fast fade, 6–18 s of
  silence) and creeps back in (on for 25–60 s) — tension from the dropouts.
- **Doors** (`door.gd`): creak on player toggle, loud slam when the entity
  shoves one. Speaker sits on the panel.
- **Ambience** (`scripts/ambience.gd`, node in `player.tscn`): constant
  roomtone + faint fluorescent buzz (non-3D), plus a random distant one-shot
  (flicker/creak/clank/drip) every 7–20 s at a random 3D spot 8–25 m away.
- Volumes/distances are inline in those scripts (volume_db, unit_size,
  max_distance, stride lengths, bpm range) — tune there.

## Menus — Maaack's Menus Template (July 2026)
- Addon lives at `addons/maaacks_menus_template/` (v1.4.6). Enabled in
  project.godot along with its 4 autoloads (AppConfig, SceneLoader,
  ProjectMusicController, ProjectUISoundController). Its install wizard is
  disabled (`maaacks_menus_template/disable_install_wizard`) — wired by hand.
- **Main scene is now the addon's example main menu**
  (`examples/scenes/menus/main_menu/main_menu_with_animations.tscn`).
  New Game loads `res://main.tscn` — that path is set as `game_scene_path`
  in the addon's `app_config.tscn` (NOT in the menu scene).
- **Pause menu**: `PauseMenuController` node in `player.tscn` points at the
  example `pause_menu.tscn`. Esc opens it (`ui_cancel`), pauses the tree,
  and has Resume/Restart/Options/Main Menu/Exit.
- `player.gd` frees the mouse on NOTIFICATION_PAUSED, recaptures on
  UNPAUSED, and frees it in `_exit_tree` (so the main menu is clickable
  after leaving the level). The old Esc mouse-toggle is gone.
- Menu title is overridden to "urbex gone wrong" and the subtitle is
  hidden (both via node overrides at the bottom of
  `examples/.../main_menu_with_animations.tscn` — auto_update off on
  TitleLabel, SubTitleLabel visible=false).
- **Menu music (July 2026)**: `audio/music/801947__...on-dead-air.wav`,
  loaded at runtime + looped in `cctv_menu.gd _ready()` (−8 dB). It lives in
  the menu scene, so it stops on New Game automatically.
- **CCTV menu background (July 2026)**: a `CCTVLayer` CanvasLayer (layer −1,
  added at the bottom of the menu .tscn) runs `scripts/cctv_menu.gd` — cycles
  3 security-camera stills (lobby / spine corridor / courtyard) every ~6 s
  with a static burst between them, plus CAM label, blinking REC and a
  ticking timestamp. Look = `shaders/cctv.gdshader` (grey-green, scanlines,
  grain, rolling bar, vignette). Stills live in `assets/cctv_*.png`, made by
  running `tools/cctv_shots.tscn` once (like the builder — edit its SHOTS
  list to move cameras, rerun after map changes). Stills are loaded with
  `Image.load_from_file`, so no editor import step is needed.

## Player step-climbing (`scripts/player.gd`)
`_try_step_up()` lifts the player onto obstacles ≤ `step_height` (0.3 m)
before `move_and_slide()`; `floor_snap_length = 0.5` keeps them stuck to
steps going down. Stairs rise 0.205 — comfortably within range.

## Key tunables
- Map layout: data tables in `scripts/build_map.gd` (then re-run the builder).
- VHS look: `FlipScreen` shader params in `scenes/player.tscn`.
- Entity: exports in `entity.gd` (`walk_speed`, `chase_speed`, `lurk_distance`,
  `chase_trigger`, `teleport_min/max`…).
- Player: exports in `player.gd` (`move_speed`, `step_height`…).
- Doors: `open_angle` per door; shove distance (2.2) in `door.gd`.

## Known harmless warnings
One navmesh bake warning on launch (agent_max_climb floored to voxel units).
Cosmetic. A clean run shows ONLY this one.

## Known issues / things to watch
- Entity has no physical collision body (navmesh-steered). If it visibly
  clips a wall, the fix is a real CharacterBody3D.
- Door leaves may clip the player if one swings into them (static body tween).
- "Press [E] to open/close/collect" prompt now works (`_update_prompt()` in
  player.gd, same ray as `_try_interact`).
- Elevator interiors and a 2 m sliver west of the SW stairwell are sealed
  dead space (intentional).

## Style / collaboration notes
- The user is new-ish to Godot — annotate code in plain, simple language.
  Keep replies concise. Don't overcomplicate.
- Workflow: edit files → run via Godot MCP → check debug output → report.
  The user tests in-game and sends screenshots; values get tuned iteratively.
- The Linux sandbox/bash is unavailable on this machine; use file tools.

## Status / next ideas (not done yet)
- (Catch reaction/jumpscare DONE July 2026 — see the entity AI section.)
- Props, abandoned-hospital dressing (textures done July 2026).
- Wall/floor/ceiling **normal + roughness EXR maps aren't imported yet**
  (`valid=false` in their .import files — editor likely blocked by the
  Blender-path popup for the .blend files). The builder skips them and
  prints a NOTE; once the editor imports them, re-run the builder and the
  full PBR look appears. Colour maps already work.
- (Battery drain, flashlight and the real entity model are DONE, July 2026.)
- Replace synthesized placeholder sounds with real recordings.
- Skin Maaack's menus to match the horror look (they're default-themed).
