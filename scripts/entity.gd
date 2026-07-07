# The entity - an invisible stalker, only visible through the camcorder.
# (All meshes are on render layer 3, which only the camcorder feed camera draws.)
#
# How it behaves:
#  - STALK: walks toward you at YOUR walking pace, but stops and lurks about
#    lurk_distance away, staring at you. The longer it goes without being
#    filmed, the closer it dares to creep.
#  - CHASE: once it is within chase_trigger metres it sprints straight at you,
#    and inside lunge_distance it lunges even faster. Within catch_distance
#    it GETS you: instant jumpscare (its screaming face fills the screen),
#    then the death screen and back to the main menu.
#  - FLEE: the instant you film it, the camera "hurts" it - it panics and
#    sprints for cover at twice your walking speed.
#  - TELEPORT: the moment it is FULLY out of the camera's sight (a wall in
#    between is enough, or the camera going back down), it vanishes and
#    reappears far away - always somewhere inside the building with room to
#    stand. It then stays calm for teleport_cooldown seconds (stalking only),
#    and THEN turns relentless and hunts you down from anywhere.
#
# Every page the player collects makes it 10% faster and more aggressive,
# up to +50% after all 5 (see set_rage, called by page_manager.gd).
#
# Movement uses a NavigationAgent3D so it walks AROUND walls, and it follows
# the path's height so it can use the stairs between floors.

extends Node3D

enum State { STALK, CHASE, FLEE }

# --- speeds (metres per second) --------------------------------------------
@export var walk_speed: float = 3.0    # stalking pace = the player's walk speed
@export var chase_speed: float = 6.0   # sprint when it gets close (2x walk)
@export var lunge_speed: float = 8.0   # final burst right next to you
@export var flee_speed: float = 8.0    # running from the camera (filming it makes it BOLT)

# --- stalking distances (metres) --------------------------------------------
@export var lurk_distance: float = 14.0  # where it likes to hover and stare
@export var lurk_min: float = 9.0        # creeping shrinks the hover ring to this
@export var creep_rate: float = 0.15     # how fast the ring shrinks (m per second)
@export var chase_trigger: float = 10.0  # closer than this -> it sprints at you
@export var lunge_distance: float = 2.0  # closer than this -> full lunge
@export var chase_exit: float = 14.0     # get further than this mid-chase -> it calms down

# --- camera / vision ---------------------------------------------------------
@export var view_angle_deg: float = 45.0  # how wide the camera's "seen" cone is
@export var point_blank: float = 3.0      # camera up this close always counts as seen
@export var evade_distance: float = 7.0   # how far it looks for a hiding spot
@export var teleport_delay: float = 0.3   # fully hidden for this long -> teleport away
@export var teleport_min: float = 35.0    # teleport lands at least this far from you
@export var teleport_max: float = 55.0    # ...and at most this far
@export var teleport_cooldown: float = 20.0  # calm-down time after a teleport (no chasing)
@export var catch_distance: float = 1.0   # closer than this -> it GETS you (jumpscare)

const MENU_SCENE := "res://addons/maaacks_menus_template/examples/scenes/menus/main_menu/main_menu_with_animations.tscn"

# --- runtime references ---
var player: Node3D
var camera: Camera3D
var camcorder: Node

# --- state ---
var state: int = State.STALK
var evade_target: Vector3 = Vector3.ZERO
var repick_timer: float = 0.0
var flee_stuck: float = 0.0         # time spent frozen in full view while fleeing
var hidden_time: float = 0.0        # how long it has been fully out of sight
var lurk_current: float = 14.0      # the current (shrinking) hover distance
var relentless: bool = false        # after a teleport: chase no matter the distance
var cooldown: float = 0.0           # seconds left of post-teleport calm (no chasing)
var rage_mult: float = 1.0          # 1.0 -> 1.5 as pages get collected

# --- the real monster model (assets/smily_horror_monster.glb) ---
# Loaded at runtime with GLTFDocument (no editor import step - same trick as
# the sounds and CCTV stills). We DON'T use the one animation it ships with;
# we pose its bones in code every frame, so all the twitchy movement,
# state changes and footstep timing stay exactly as they are.
const MODEL_PATH := "res://assets/smily_horror_monster.glb"
const MODEL_FILE_HEIGHT := 117.61  # how tall the raw file is (it's HUGE)
const MODEL_FILE_FEET := 14.13     # its feet sit this far below zero in the file
@export var model_height: float = 2.2   # how tall it should stand in the game
@export var model_yaw: float = 0.0      # manual extra twist if the auto-facing is ever off

var face_yaw: float = 0.0               # the computed "which way it faces" fix (radians)

var model_wrap: Node3D = null      # wrapper we scale/turn/bob as one thing
var skel: Skeleton3D = null        # the model's skeleton (null = model missing)
var bone_id: Dictionary = {}       # short name -> bone index
var bone_rest: Dictionary = {}     # short name -> rest rotation (Quaternion)
var wrap_base_y: float = 0.0       # wrapper height that puts its feet on the floor

# --- sound ---
var step_sounds: Array = []          # the 3 footstep variations
var step_side: float = 0.0           # tracks the stride so we know when a foot lands
var steps_audio: AudioStreamPlayer3D
var roar_audio: AudioStreamPlayer3D
var scare_audio: AudioStreamPlayer

# --- the catch / jumpscare ---
# The scare is pure screen-space: the model is yanked out of the level into
# an empty SubViewport world with its own camera parked right in front of
# its face, and THAT picture is pasted over the whole screen. No walls, no
# fog, nothing to clip into - just the screaming face.
var caught: bool = false        # it reached the player - game over sequence
var scare_timer: float = 0.0
var death_shown: bool = false
var scare_fx: ShaderMaterial = null    # the fullscreen static (flickered each frame)
var scare_layer: CanvasLayer = null
var scare_view: SubViewport = null     # the face's own little world
var scare_cam: Camera3D = null         # the camera staring at the face
const SCARE_FOV := 33.0                # tight zoom - the face fills the frame
const SCARE_CAM_DIST := 0.38           # how far the camera sits from the face

# --- animation ---
var duck: float = 0.0        # 0 = upright, 1 = squeezed down (under doorways)
var walk_phase: float = 0.0
var anim_time: float = 0.0
var twitch_timer: float = 0.0
# Each twitch snaps the head/spine to a random pose, which then bleeds away.
var head_target: Vector3 = Vector3.ZERO
var head_jerk: Vector3 = Vector3.ZERO
var spine_target: Vector3 = Vector3.ZERO
var spine_jerk: Vector3 = Vector3.ZERO

@onready var nav_agent: NavigationAgent3D = $NavAgent
@onready var rig: Node3D = $Rig
@onready var pelvis: Node3D = $Rig/Pelvis
@onready var spine: Node3D = $Rig/Pelvis/Spine
@onready var head: Node3D = $Rig/Pelvis/Spine/Head
@onready var shoulder_l: Node3D = $Rig/Pelvis/Spine/ShoulderL
@onready var shoulder_r: Node3D = $Rig/Pelvis/Spine/ShoulderR
@onready var hip_l: Node3D = $Rig/Pelvis/HipL
@onready var hip_r: Node3D = $Rig/Pelvis/HipR
@onready var knee_l: Node3D = $Rig/Pelvis/HipL/KneeL
@onready var knee_r: Node3D = $Rig/Pelvis/HipR/KneeR


func _ready() -> void:
	# Doors look for us in this group so they know when to get shoved open.
	add_to_group("entity")
	lurk_current = lurk_distance
	_find_player()
	_setup_audio()
	_load_model()


# Loads the real monster model and swaps it in for the placeholder box rig.
# If anything goes wrong it just warns and keeps the boxes.
func _load_model() -> void:
	var doc := GLTFDocument.new()
	var gltf := GLTFState.new()
	if doc.append_from_file(MODEL_PATH, gltf) != OK:
		push_warning("ENTITY: couldn't read the monster model - using the box rig")
		return
	var scene := doc.generate_scene(gltf)
	if scene == null:
		push_warning("ENTITY: monster model has no scene - using the box rig")
		return

	# The wrapper lets us scale/turn/bob the whole model as one thing.
	# The raw file is ~118 m tall, so it gets shrunk down to model_height.
	var s := model_height / MODEL_FILE_HEIGHT
	model_wrap = Node3D.new()
	model_wrap.name = "Model"
	model_wrap.scale = Vector3.ONE * s
	wrap_base_y = MODEL_FILE_FEET * s  # lift it so its feet sit on the floor
	model_wrap.position.y = wrap_base_y
	model_wrap.add_child(scene)
	add_child(model_wrap)

	# Render layer 3 = only the camcorder's feed camera draws it. No shadows.
	for mi in model_wrap.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 4
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Stop the one baked-in animation - the bones are ours now.
	for ap in model_wrap.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).stop()

	# Find the skeleton, remember the bones we pose and their rest rotations.
	var skels := model_wrap.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		push_warning("ENTITY: no skeleton in the model - using the box rig")
		model_wrap.queue_free()
		model_wrap = null
		return
	skel = skels[0]
	var names := {
		"belly": "belly_02", "chest": "chest_03", "neck": "neck_04",
		"head": "head_05", "jaw": "jaw_06",
		"arm_l": "Arm.L_09", "arm_r": "Arm.R_022",
		"forearm_l": "Forearm.L_010", "forearm_r": "Forearm.R_023",
		"leg_l": "leg.L_036", "leg_r": "leg.R_041",
		"shin_l": "sheen.L_037", "shin_r": "sheen.R_042",
	}
	for key in names:
		var idx: int = skel.find_bone(names[key])
		if idx < 0:
			push_warning("ENTITY: bone '%s' not found in the model" % names[key])
			continue
		bone_id[key] = idx
		bone_rest[key] = skel.get_bone_rest(idx).basis.get_rotation_quaternion()

	# Which way does the mesh actually FACE? Models come in pointing any
	# direction, so we work it out from the skeleton itself: a humanoid's
	# toes always point forward of its body. Then the wrapper is turned so
	# that forward lines up with the way the entity walks (-Z).
	# (model_yaw is a manual extra twist on top, normally 0.)
	# Both feet are averaged, so a splayed-out foot can't skew the answer.
	model_wrap.rotation.y = 0.0
	var fwd := Vector3.ZERO
	for pair in [["foot.L_038", "toes.L_039"], ["foot.R_043", "toes.R_044"]]:
		var foot_i: int = skel.find_bone(pair[0])
		var toe_i: int = skel.find_bone(pair[1])
		if foot_i >= 0 and toe_i >= 0:
			fwd += _bone_rest_global(toe_i).origin - _bone_rest_global(foot_i).origin
	if fwd.length() > 0.0001:
		var f: Vector3 = global_transform.basis.inverse() * (skel.global_transform.basis * fwd)
		f.y = 0.0
		if f.length() > 0.001:
			model_wrap.rotation.y = PI - atan2(f.x, f.z)
	model_wrap.rotation.y += deg_to_rad(model_yaw)
	face_yaw = model_wrap.rotation.y

	# The model replaces the placeholder boxes.
	rig.visible = false
	print("ENTITY: monster model loaded (%d bones mapped, facing fix %.0f deg)" %
			[bone_id.size(), rad_to_deg(face_yaw)])


# A bone's rest transform in skeleton space (its rest multiplied up the
# parent chain) - the model's untouched T-pose, unaffected by our posing.
func _bone_rest_global(idx: int) -> Transform3D:
	var t: Transform3D = skel.get_bone_rest(idx)
	var p: int = skel.get_bone_parent(idx)
	while p >= 0:
		t = skel.get_bone_rest(p) * t
		p = skel.get_bone_parent(p)
	return t


# Turn one bone away from its rest pose by (x, y, z) radians.
func _pose(bone_name: String, x: float, y: float = 0.0, z: float = 0.0) -> void:
	if not bone_id.has(bone_name):
		return
	var q: Quaternion = bone_rest[bone_name] * Quaternion.from_euler(Vector3(x, y, z))
	skel.set_bone_pose_rotation(bone_id[bone_name], q)


# Builds the entity's two "speakers" in code: one for footsteps, one for
# the roar. 3D speakers get quieter with distance automatically.
func _setup_audio() -> void:
	for i in 3:
		step_sounds.append(load("res://audio/step_entity_%d.res" % (i + 1)))

	steps_audio = AudioStreamPlayer3D.new()
	steps_audio.max_distance = 30.0  # completely silent beyond 30 m
	steps_audio.unit_size = 6.0      # stays fairly loud out to ~6 m, then fades
	add_child(steps_audio)

	roar_audio = AudioStreamPlayer3D.new()
	roar_audio.stream = load("res://audio/roar.res")  # one angry roar (real recording)
	roar_audio.max_distance = 60.0  # a roar carries much further than steps
	roar_audio.unit_size = 10.0
	add_child(roar_audio)

	# The death scream. Non-3D and LOUD - when this plays it's right in
	# your face, no distance falloff wanted.
	scare_audio = AudioStreamPlayer.new()
	scare_audio.stream = load("res://audio/jumpscare.res")
	scare_audio.volume_db = 3.0
	add_child(scare_audio)


# One foot just hit the floor - play a random footstep variation.
func _play_step() -> void:
	steps_audio.stream = step_sounds[randi() % step_sounds.size()]
	steps_audio.pitch_scale = randf_range(0.9, 1.1)  # tiny pitch change so no two steps match
	# It stomps harder when it's charging at you.
	steps_audio.volume_db = 4.0 if state == State.CHASE else 0.0
	steps_audio.play()


# Used by the player script: is it sprinting at the player right now?
# (That's what turns the heartbeat sound on.)
func is_chasing() -> bool:
	return state == State.CHASE


# Called by page_manager.gd each time a page is collected.
# Each page = +10% speed and aggression, capped at +50% (5 pages).
func set_rage(pages: int) -> void:
	rage_mult = 1.0 + 0.1 * clampi(pages, 0, 5)


func _find_player() -> void:
	player = get_tree().get_first_node_in_group("player")
	if player != null:
		camera = player.get_node_or_null("Head/Camera3D")
		camcorder = player.get_node_or_null("Head/Camera3D/Camcorder")


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		_find_player()
		return

	# Once it has you, the only thing left to run is the scare itself.
	if caught:
		_scare_tick(delta)
		return

	var moving: bool = false
	var dist: float = global_position.distance_to(player.global_position)
	cooldown = maxf(cooldown - delta, 0.0)

	# CLOSE ENOUGH TO TOUCH -> it got you. (Not while fleeing the camera -
	# brushing past you mid-panic shouldn't kill.)
	if dist < catch_distance and state != State.FLEE:
		_catch_player()
		return

	# Being filmed beats everything - drop what we're doing and run.
	if state != State.FLEE and _being_watched():
		state = State.FLEE
		relentless = false  # the camera breaks its chase
		hidden_time = 0.0
		repick_timer = 0.0
		flee_stuck = 0.0
		roar_audio.play()  # it roars in pain the moment the camera hits it
		_choose_evade()

	match state:
		State.STALK:
			# The hover ring slowly shrinks the longer it stays unfilmed,
			# so eventually it creeps into chase range on its own.
			# (rage_mult: collected pages make everything here angrier.)
			lurk_current = move_toward(lurk_current, lurk_min, creep_rate * rage_mult * delta)
			if cooldown > 0.0:
				# Post-teleport calm: it stalks, but will NOT start a chase.
				pass
			elif relentless:
				# The calm just ran out after a teleport - back on the hunt.
				state = State.CHASE
			elif dist < chase_trigger * rage_mult:
				state = State.CHASE
			elif dist > lurk_current + 1.0:
				# Too far away - walk closer (at the player's walking pace).
				moving = _navigate_to(player.global_position, walk_speed * rage_mult, delta)
			else:
				# Close enough - stand there and stare at you.
				_face(player.global_position)

		State.CHASE:
			# Sprint at the player. Full-on lunge for the last stretch.
			var spd: float = lunge_speed if dist < lunge_distance else chase_speed
			moving = _navigate_to(player.global_position, spd * rage_mult, delta)
			if dist > chase_exit and not relentless:
				# You got away - back to lurking from a respectful distance.
				# (After a teleport it's relentless: it NEVER calms down
				# until the camera drives it off again.)
				state = State.STALK
				lurk_current = lurk_distance

		State.FLEE:
			if _fully_hidden():
				# Completely out of the camera's sight. Wait a beat, then vanish.
				hidden_time += delta
				if hidden_time >= teleport_delay:
					_teleport_far()
			else:
				# Still on camera - keep sprinting for cover.
				hidden_time = 0.0
				repick_timer += delta
				moving = _navigate_to(evade_target, flee_speed, delta)
				# Standing still in full view = the chosen spot is bad
				# (this is what froze it on the stairs). Count how long
				# it's been frozen; repick sooner and search wider and
				# wider until it finds somewhere it can actually run.
				flee_stuck = 0.0 if moving else flee_stuck + delta
				var repick_at: float = 0.15 if flee_stuck > 0.2 else 0.4
				if repick_timer >= repick_at:
					repick_timer = 0.0
					_choose_evade(minf(1.0 + flee_stuck * 2.0, 3.0))

	_animate(delta, moving)


# --- the catch: instant in-your-face jumpscare, then game over ------------

# Everything here happens in ONE frame - that's what makes it snap:
# the player freezes, the monster is suddenly filling the screen with its
# jaw wide open, and the death scream is already playing.
func _catch_player() -> void:
	caught = true
	scare_timer = 0.0

	# Freeze the player where they stand: no walking, no looking around.
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	if camcorder != null:
		camcorder.set_process_unhandled_input(false)

	scare_layer = CanvasLayer.new()
	scare_layer.layer = 90  # under the death screen (100)
	add_child(scare_layer)

	# --- the face, rendered in its own empty world ---
	if model_wrap != null:
		scare_view = SubViewport.new()
		scare_view.size = Vector2i(640, 360)  # low-res on purpose: grainy VHS look
		scare_view.own_world_3d = true        # empty world - only the monster exists here
		scare_layer.add_child(scare_view)

		# Pull the model out of the level and into the face-world.
		model_wrap.get_parent().remove_child(model_wrap)
		scare_view.add_child(model_wrap)
		model_wrap.position = Vector3(0, wrap_base_y, 0)
		model_wrap.rotation = Vector3(0, face_yaw, 0)  # the computed fix: face points -Z here

		# Where the head is inside this little world.
		var head_pos: Vector3 = model_wrap.position + Vector3(0, model_height * 0.75, 0)
		if bone_id.has("head"):
			head_pos = skel.global_transform * skel.get_bone_global_pose(bone_id["head"]).origin

		# A camera parked right in front of the face, staring at it...
		scare_cam = Camera3D.new()
		scare_cam.fov = SCARE_FOV
		scare_view.add_child(scare_cam)
		scare_cam.position = head_pos + Vector3(0, 0.02, -SCARE_CAM_DIST)
		scare_cam.look_at(head_pos, Vector3.UP)

		# ...and a hard light so the face reads bright against pure black.
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(0.9, 0.87, 0.8)
		lamp.light_energy = 2.5
		lamp.omni_range = 4.0
		lamp.position = scare_cam.position
		scare_view.add_child(lamp)

		# Paste that picture over the whole screen.
		var face_rect := TextureRect.new()
		face_rect.texture = scare_view.get_texture()
		face_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face_rect.stretch_mode = TextureRect.STRETCH_SCALE
		face_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scare_layer.add_child(face_rect)

	# Fullscreen VHS static on top of the face.
	var static_rect := ColorRect.new()
	static_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	static_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scare_fx = ShaderMaterial.new()
	scare_fx.shader = load("res://shaders/scare_static.gdshader")
	static_rect.material = scare_fx
	scare_layer.add_child(static_rect)

	# The scream starts THIS frame.
	scare_audio.play()


# Runs every physics frame while the scare plays: rattle the monster
# violently in your face, then cut to the death screen.
func _scare_tick(delta: float) -> void:
	scare_timer += delta
	anim_time += delta

	if skel != null and scare_cam != null:
		# Jaw as wide as it goes, head shaking hard, whole body rattling.
		_pose("jaw", 1.1)
		_pose("head", 0.35 + randf_range(-0.12, 0.12),
				randf_range(-0.12, 0.12), randf_range(-0.12, 0.12))
		_pose("belly", -0.25)
		_pose("chest", -0.2)
		model_wrap.position.x = randf_range(-0.04, 0.04)
		model_wrap.position.z = randf_range(-0.04, 0.04)  # lurches at/away from the lens
		# The zoom judders too - never steady for a single frame.
		scare_cam.fov = SCARE_FOV + randf_range(-2.5, 2.5)

	if scare_fx != null:
		# Mostly mid-strength static, with hard spikes of a full white-out.
		var burst: float = 1.0 if randf() < 0.12 else randf_range(0.3, 0.55)
		scare_fx.set_shader_parameter("intensity", burst)

	# Hold the face for a beat, then hard cut to black.
	if scare_timer >= 1.1 and not death_shown:
		_death_screen()


# Black screen, "it got you.", then back to the main menu.
func _death_screen() -> void:
	death_shown = true
	if scare_layer != null:
		scare_layer.visible = false  # static off - dead silence and black
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	var black := ColorRect.new()
	black.color = Color(0, 0, 0)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(black)

	var text := Label.new()
	text.text = "it got you."
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 34)
	text.add_theme_color_override("font_color", Color(0.6, 0.1, 0.08))
	layer.add_child(text)

	# Let the scream ring out over the black, then back to the menu.
	var tw := create_tween()
	tw.tween_interval(2.8)
	tw.tween_callback(func() -> void:
		get_tree().change_scene_to_file(MENU_SCENE))


# --- movement ------------------------------------------------------------

# Path toward a target using the nav agent. Returns true while still moving.
# Follows the path's height too, so the entity can walk the stairs.
func _navigate_to(target: Vector3, spd: float, delta: float) -> bool:
	nav_agent.target_position = target

	if nav_agent.is_navigation_finished():
		return false

	var next_point: Vector3 = nav_agent.get_next_path_position()
	var to_next: Vector3 = next_point - global_position

	if to_next.length() < 0.05:
		return false

	# Walk straight along the 3D line to the next point. On flat floor
	# that's normal walking; on the stair links it follows the ramp's
	# slope exactly - so it can't fly across the shaft or clip the slab
	# (the old code moved flat first and fixed the height separately).
	var dir: Vector3 = to_next.normalized()
	var step: Vector3 = dir * spd * delta
	if step.length() > to_next.length():
		step = to_next  # don't overshoot the point
	global_position += step

	# Only turn to face where we're going horizontally.
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat.length() > 0.05:
		_face(global_position + flat)
	return true


func _face(point: Vector3) -> void:
	var look_point: Vector3 = Vector3(point.x, global_position.y, point.z)
	if global_position.distance_to(look_point) > 0.1:
		look_at(look_point, Vector3.UP)


# --- watching / line of sight --------------------------------------------

func _camera_raised() -> bool:
	if camcorder == null:
		return false
	var raise_val = camcorder.get("raise_amount")
	return raise_val != null and raise_val >= 0.5


# Is the player actively filming us right now?
func _being_watched() -> bool:
	if camera == null or not _camera_raised():
		return false

	var to_ent: Vector3 = global_position - camera.global_position
	var dist: float = to_ent.length()

	# Point-blank with the camera up always counts.
	if dist < point_blank:
		return true

	# Inside the view cone?
	to_ent = to_ent.normalized()
	var cam_forward: Vector3 = -camera.global_transform.basis.z
	if cam_forward.dot(to_ent) < cos(deg_to_rad(view_angle_deg)):
		return false

	# Any part of the body visible?
	return not _is_hidden(camera.global_position, global_position)


# Are we COMPLETELY out of the camera's sight? True if the camera is down
# (we're invisible to the naked eye anyway), or a wall hides every part of us.
func _fully_hidden() -> bool:
	if not _camera_raised():
		return true
	return _is_hidden(camera.global_position, global_position)


# True only if the view from "from" to the body standing at "point" is blocked
# at feet, chest AND head height - i.e. fully behind something.
# "mask" picks what counts as a blocker: everything by default, or pass 1
# for walls only (so door panels don't count).
func _is_hidden(from: Vector3, point: Vector3, mask: int = 0xFFFFFFFF) -> bool:
	var space := get_world_3d().direct_space_state
	for h in [0.2, 0.9, 1.6]:
		var query := PhysicsRayQueryParameters3D.create(from, point + Vector3(0, h, 0))
		query.collision_mask = mask
		query.exclude = [player.get_rid()]
		if space.intersect_ray(query).is_empty():
			return false  # this ray reached us - that part is visible
	return true


# Pick a spot to run to that breaks the camera's line of sight. We sample points
# around us, snap them to the navmesh, and prefer ones hidden from the camera
# AND far from the player. "spread" widens the search ring (used when it's
# been standing frozen - look further away for somewhere to run).
func _choose_evade(spread: float = 1.0) -> void:
	var cam_pos: Vector3 = camera.global_position
	var my: Vector3 = global_position
	var player_pos: Vector3 = player.global_position
	var map: RID = nav_agent.get_navigation_map()

	var best_hidden = null
	var best_hidden_score: float = -INF
	var best_any: Vector3 = my
	var best_any_score: float = -INF

	var samples: int = 16
	for i in samples:
		var ang: float = TAU * float(i) / float(samples)
		var dir: Vector3 = Vector3(cos(ang), 0.0, sin(ang))
		for dist in [evade_distance * spread, evade_distance * 0.6 * spread]:
			var cand: Vector3 = NavigationServer3D.map_get_closest_point(map, my + dir * dist)
			if not _inside_building(cand):
				continue  # snapped onto the roof or past the walls - never go there
			if cand.distance_to(my) < 2.0:
				continue  # basically where we already stand - "running" there = freezing
			var score: float = cand.distance_to(player_pos) - my.distance_to(cand) * 0.2
			# mask 1 = only WALLS count as cover here. Door panels don't,
			# so it never picks "behind an open door" as a hiding spot
			# (that made it hover at doorways looking stuck).
			if _is_hidden(cam_pos, cand, 1):
				if score > best_hidden_score:
					best_hidden_score = score
					best_hidden = cand
			else:
				if score > best_any_score:
					best_any_score = score
					best_any = cand

	if best_hidden != null:
		evade_target = best_hidden
	elif best_any_score > -INF:
		evade_target = best_any
	else:
		# Everything nearby got rejected (cornered - e.g. mid-staircase).
		# No clever hiding then: just bolt straight away from the player.
		var away: Vector3 = my - player_pos
		away.y = 0.0
		if away.length() < 0.5:
			away = Vector3.FORWARD
		evade_target = NavigationServer3D.map_get_closest_point(
			map, my + away.normalized() * evade_distance * 2.0)


# Is the ceiling LOW right here or just ahead? True under doorway headers
# (they start at 2.2 m) - normal ceilings are 4 m up, so they never trigger.
# Checked at our feet AND ~1 m ahead, so the duck starts before the doorway.
func _low_overhead() -> bool:
	var space := get_world_3d().direct_space_state
	var fwd: Vector3 = -global_transform.basis.z
	for at in [global_position, global_position + fwd * 1.0]:
		var q := PhysicsRayQueryParameters3D.create(
			at + Vector3(0, 0.1, 0), at + Vector3(0, 2.4, 0))
		q.collision_mask = 1  # walls/headers only, not door panels
		if not space.intersect_ray(q).is_empty():
			return true
	return false


# Is this point really inside the building? Rejects the roof top (too
# high) and anything past the outer walls. Safety net on top of the
# navmesh bake limits in nav_baker.gd - a teleport can NEVER land outside.
func _inside_building(pos: Vector3) -> bool:
	return pos.y < 4.5 and absf(pos.x) < 54.5 and absf(pos.z) < 37.0


# Does the entity have room to STAND at this spot? We check for 2 m of
# clear air above it (no ceiling in its head) and half a metre of space
# in all 4 directions (not half-inside a wall).
func _spot_has_room(pos: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	# Headroom check: straight up.
	var up := PhysicsRayQueryParameters3D.create(
		pos + Vector3(0, 0.1, 0), pos + Vector3(0, 2.1, 0))
	up.collision_mask = 1  # walls/ceilings only
	if not space.intersect_ray(up).is_empty():
		return false
	# Elbow-room check: 4 short rays out from chest height.
	var chest: Vector3 = pos + Vector3(0, 0.9, 0)
	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var q := PhysicsRayQueryParameters3D.create(chest, chest + dir * 0.5)
		q.collision_mask = 1
		if not space.intersect_ray(q).is_empty():
			return false
	return true


# Vanish and reappear somewhere far from the player. We try random navmesh
# points in a ring around the player (the navmesh only exists INSIDE the
# building, so it can never land outside), keep only spots with room to
# stand, and strongly prefer ones the camera can't see. Then it goes
# straight back to hunting the player - no cooldown.
func _teleport_far() -> void:
	var map: RID = nav_agent.get_navigation_map()
	var player_pos: Vector3 = player.global_position
	var best: Vector3 = global_position
	var best_score: float = -INF

	for i in 24:
		var ang: float = randf() * TAU
		var d: float = randf_range(teleport_min, teleport_max)
		var cand: Vector3 = NavigationServer3D.map_get_closest_point(
			map, player_pos + Vector3(cos(ang), 0.0, sin(ang)) * d)
		var pd: float = cand.distance_to(player_pos)
		if not _inside_building(cand):
			continue  # roof or outside the walls - never land there
		if pd < teleport_min * 0.6:
			continue  # snapped somewhere too close to the player - skip it
		if not _spot_has_room(cand):
			continue  # would clip a wall or ceiling - skip it
		var score: float = pd
		if camera != null and _is_hidden(camera.global_position, cand):
			score += 1000.0  # heavily prefer spots the camera can't see
		if score > best_score:
			best_score = score
			best = cand

	if best_score == -INF:
		# Every sample was bad (rare). Stay put and retry very soon.
		hidden_time = teleport_delay * 0.5
		return

	global_position = best
	# It lands far away and takes a breather (teleport_cooldown seconds of
	# plain stalking, no chasing). When the calm runs out it turns RELENTLESS
	# and hunts you from anywhere until the camera drives it off again.
	# (Doors won't stop it - door.gd slams them open as it approaches.)
	state = State.STALK
	lurk_current = lurk_distance
	relentless = true
	cooldown = teleport_cooldown
	hidden_time = 0.0


# --- animation -----------------------------------------------------------
# Creature-like and twitchy: hunched spine, head peering up from under the
# hunch with a sideways tilt, arms hanging forward, an uneven limping gait,
# and random jerky twitches. Everything gets far more violent while it's
# being filmed (FLEE) - like the camera is burning it.

func _animate(delta: float, moving: bool) -> void:
	anim_time += delta
	var panic: bool = state == State.FLEE
	var frantic: bool = panic or state == State.CHASE

	# Hurried, uneven stride. The multiplier wobbles so steps never feel even.
	if moving:
		var gait: float = 16.0 if frantic else 9.0
		walk_phase += delta * gait * (0.8 + 0.4 * sin(anim_time * 7.3) * sin(anim_time * 2.9))

		# A foot lands every time the stride wave flips sign - play a step
		# right then, so the sound matches the legs exactly (and speeds up
		# automatically when it sprints).
		var side: float = signf(sin(walk_phase))
		if side != step_side:
			_play_step()
		step_side = side

	# --- random twitches: snap into a jerk, then let it bleed away ---
	twitch_timer -= delta
	if twitch_timer <= 0.0:
		# When panicking it twitches almost constantly and much harder.
		twitch_timer = randf_range(0.05, 0.25) if panic else randf_range(0.4, 2.2)
		var s: float = 1.0 if panic else 0.5
		head_target = Vector3(randf_range(-0.5, 0.7), randf_range(-1.0, 1.0), randf_range(-0.8, 0.8)) * s
		spine_target = Vector3(randf_range(-0.2, 0.3), randf_range(-0.35, 0.35), randf_range(-0.3, 0.3)) * s

	# Snap INTO the pose fast (the jerk)...
	head_jerk = head_jerk.lerp(head_target, minf(1.0, delta * 30.0))
	spine_jerk = spine_jerk.lerp(spine_target, minf(1.0, delta * 25.0))
	# ...then the pose itself relaxes back toward zero.
	head_target = head_target.lerp(Vector3.ZERO, delta * 4.0)
	spine_target = spine_target.lerp(Vector3.ZERO, delta * 4.0)

	# --- ducking under doorways: something low overhead -> squeeze down ---
	# It sinks fast on the way in and straightens back up after, so it
	# visibly folds itself through door frames instead of clipping them.
	var duck_target: float = 1.0 if (moving and _low_overhead()) else 0.0
	duck = move_toward(duck, duck_target, delta * 6.0)
	pelvis.position.y = 0.9 - 0.45 * duck  # drop the whole body at the hips

	# --- posture: hunched forward, head tilted, slow uneasy sway ---
	# Ducking bends the spine down even harder.
	var hunch: float = (-0.55 if moving else -0.4) - 0.5 * duck
	spine.rotation = Vector3(
		hunch + sin(anim_time * 1.7) * 0.06,
		0.0,
		sin(anim_time * 1.1) * 0.08) + spine_jerk
	# Head pitches back up so it stares at you from under the hunch
	# (even harder while ducking - it never stops looking at you).
	head.rotation = Vector3(0.5 + 0.3 * duck, 0.0, 0.15) + head_jerk

	# --- limbs: limping legs, arms dangling forward and slightly out ---
	var leg_swing: float = 0.9 if moving else 0.0
	var arm_swing: float = 0.75 if moving else 0.1
	hip_l.rotation.x = sin(walk_phase) * leg_swing
	hip_r.rotation.x = sin(walk_phase + PI) * leg_swing * 0.85  # right leg drags a bit
	knee_l.rotation.x = max(0.0, -sin(walk_phase)) * 1.1
	knee_r.rotation.x = max(0.0, -sin(walk_phase + PI)) * 0.8
	shoulder_l.rotation.x = sin(walk_phase + PI) * arm_swing - 0.25
	shoulder_r.rotation.x = sin(walk_phase) * arm_swing - 0.25
	shoulder_l.rotation.z = 0.18 + sin(anim_time * 5.1) * 0.05
	shoulder_r.rotation.z = -0.18 - sin(anim_time * 4.3) * 0.05

	# --- whole-body shiver, worst while the camera is on it ---
	var shiver: float = 0.05 if panic else 0.012
	rig.position.x = sin(anim_time * 37.0) * shiver
	rig.position.z = sin(anim_time * 29.0) * shiver
	rig.position.y = abs(sin(walk_phase)) * 0.07 if moving else sin(anim_time * 2.3) * 0.02

	# The real model (if it loaded) gets the same motion, on its bones.
	if skel != null:
		_pose_model(moving, panic, shiver)


# Poses the monster model's skeleton - the same creepy motion the box rig
# uses: hunched curving spine, head staring up from under it, limping legs,
# dangling arms, random jerks, and a jaw that hangs open when it's worked up.
func _pose_model(moving: bool, panic: bool, shiver: float) -> void:
	# --- spine: the hunch is split over two bones so the back CURVES ---
	var hunch: float = (-0.55 if moving else -0.4) - 0.5 * duck
	_pose("belly",
			hunch * 0.5 + sin(anim_time * 1.7) * 0.03 + spine_jerk.x * 0.5,
			spine_jerk.y * 0.5,
			sin(anim_time * 1.1) * 0.04 + spine_jerk.z * 0.5)
	_pose("chest", hunch * 0.6 + spine_jerk.x * 0.5, spine_jerk.y * 0.5, spine_jerk.z * 0.5)

	# --- head: pitched back up so it never stops staring at you ---
	_pose("neck", 0.3 + 0.2 * duck)
	_pose("head",
			0.35 + 0.25 * duck + head_jerk.x * 0.7,
			head_jerk.y * 0.7,
			0.15 + head_jerk.z * 0.7)
	# Jaw hangs open a little, gaping wide while it panics or chases.
	var worked_up: bool = panic or state == State.CHASE
	_pose("jaw", 0.25 + (0.4 if worked_up else 0.0) + 0.05 * sin(anim_time * 3.1))

	# --- limbs: same limping gait as the boxes ---
	var leg_swing: float = 0.9 if moving else 0.0
	var arm_swing: float = 0.75 if moving else 0.1
	_pose("leg_l", sin(walk_phase) * leg_swing)
	_pose("leg_r", sin(walk_phase + PI) * leg_swing * 0.85)  # right leg drags
	_pose("shin_l", max(0.0, -sin(walk_phase)) * 1.1)
	_pose("shin_r", max(0.0, -sin(walk_phase + PI)) * 0.8)
	_pose("arm_l", sin(walk_phase + PI) * arm_swing - 0.25, 0.0, 0.18 + sin(anim_time * 5.1) * 0.05)
	_pose("arm_r", sin(walk_phase) * arm_swing - 0.25, 0.0, -0.18 - sin(anim_time * 4.3) * 0.05)
	_pose("forearm_l", -0.3)
	_pose("forearm_r", -0.3)

	# --- whole body: shiver, step bob, and the duck-drop under doorways ---
	model_wrap.position.x = sin(anim_time * 37.0) * shiver
	model_wrap.position.z = sin(anim_time * 29.0) * shiver
	var bob: float = abs(sin(walk_phase)) * 0.07 if moving else sin(anim_time * 2.3) * 0.02
	model_wrap.position.y = wrap_base_y + bob - 0.45 * duck
