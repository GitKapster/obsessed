# First-person player controller.
# Handles walking around and looking with the mouse.
# This script lives on the CharacterBody3D root of player.tscn.

extends CharacterBody3D

# --- Settings you can tweak ---
@export var move_speed: float = 3.0      # how fast you walk (slow = creepy)
@export var sprint_speed: float = 5.0    # how fast you run with Left Shift
@export var sprint_time: float = 5.0     # how many seconds of sprint you have
@export var jump_strength: float = 4.0   # how high a jump goes
@export var mouse_sensitivity: float = 0.003  # how fast looking turns
@export var step_height: float = 0.3     # tallest stair step we can walk up

# How much sprint you have left, in seconds. Drains while sprinting,
# refills while you're not. Starts full.
var sprint_left: float = sprint_time

# Gravity pulled from the project settings so it matches physics.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

# We grab the "Head" node so we can tilt it up/down when looking.
@onready var head: Node3D = $Head

# Stamina meter (HUD) pieces.
@onready var stamina_track: ColorRect = $HUD/StaminaTrack
@onready var stamina_fill: ColorRect = $HUD/StaminaTrack/StaminaFill

# Camera battery meter (HUD) + the camcorder it reads from.
@onready var battery_track: ColorRect = $HUD/BatteryTrack
@onready var battery_fill: ColorRect = $HUD/BatteryTrack/BatteryFill
@onready var camcorder_node: Node3D = $Head/Camera3D/Camcorder

# "Press [E] to collect" text - shown only while looking at a page.
var prompt_label: Label

# Helpers for the meter: a timer for pulsing, and the current fade level.
var hud_time: float = 0.0
var hud_alpha: float = 0.0

# --- sound ---
# These are plain (non-3D) speakers because they're OUR body - footsteps,
# breathing and heartbeat always sound "in your head", not out in the room.
var steps_audio: AudioStreamPlayer
var breath_audio: AudioStreamPlayer
var heart_audio: AudioStreamPlayer
var step_sounds: Array = []
var breath_sounds: Array = []   # calm breathing
var panic_breaths: Array = []   # gasping sprint breathing, used under stress
var step_accum: float = 0.0     # metres walked since the last footstep
var breath_timer: float = 4.0   # counts down to the next breath
var breath_flip: bool = false   # alternate between the two breath sounds
var heart_timer: float = 0.0    # counts down to the next heartbeat
var heart_level: float = 0.0    # 0 = calm, 1 = full panic heartbeat
var entity: Node3D = null       # found once, then remembered


func _ready() -> void:
	# Lock the mouse to the window and hide the cursor.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Stick to the ground a bit so we don't fly off the edge of stairs going down.
	floor_snap_length = 0.5
	_setup_audio()
	_build_prompt()


# Build the little "Press [E] to collect" label. It sits just under the
# middle of the screen and stays hidden until we're looking at a page.
func _build_prompt() -> void:
	prompt_label = Label.new()
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prompt_label.offset_top = 40.0  # nudge it just below screen centre
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 22)
	prompt_label.add_theme_color_override("font_color", Color(0.85, 0.83, 0.75))
	prompt_label.text = "Press [E] to collect"
	prompt_label.visible = false
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(prompt_label)


# Build our three body-sound speakers in code.
func _setup_audio() -> void:
	for i in 3:
		step_sounds.append(load("res://audio/step_player_%d.res" % (i + 1)))
	breath_sounds.append(load("res://audio/breath_1.res"))
	breath_sounds.append(load("res://audio/breath_2.res"))
	panic_breaths.append(load("res://audio/breath_sprint_1.res"))
	panic_breaths.append(load("res://audio/breath_sprint_2.res"))

	steps_audio = AudioStreamPlayer.new()
	add_child(steps_audio)
	breath_audio = AudioStreamPlayer.new()
	add_child(breath_audio)
	heart_audio = AudioStreamPlayer.new()
	heart_audio.stream = load("res://audio/heartbeat.res")
	add_child(heart_audio)


func _unhandled_input(event: InputEvent) -> void:
	# Mouse moved -> turn the player and tilt the head.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Left/right: rotate the whole body.
		rotate_y(-event.relative.x * mouse_sensitivity)
		# Up/down: tilt only the head.
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		# Stop the head from flipping over backwards.
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))


# The pause menu (Esc) pauses the whole game. Godot tells every node when
# that happens - we use it to free the mouse for the menu, and grab it back
# when the game resumes.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_UNPAUSED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# Leaving the level (e.g. "Main Menu" from the pause menu) - give the mouse
# back so the menu can be clicked.
func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	# Apply gravity when in the air.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump if grounded.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_strength

	# Read movement keys into a 2D direction (-1..1 on each axis).
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Turn that into a world direction relative to where we're facing.
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Sprint only when: holding Shift, actually moving, and we still have sprint left.
	var sprinting: bool = Input.is_action_pressed("sprint") and direction and sprint_left > 0.0
	if sprinting:
		# Burn sprint while running.
		sprint_left = max(sprint_left - delta, 0.0)
	else:
		# Refill sprint while not sprinting (never above the full amount).
		sprint_left = min(sprint_left + delta, sprint_time)

	# Pick the speed for this frame.
	var speed: float = sprint_speed if sprinting else move_speed

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		# No keys held -> stop quickly.
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)

	# Update the stamina and camera-battery meters on screen.
	_update_stamina_hud(sprint_left / sprint_time, sprinting, delta)
	_update_battery_hud()

	# Show/hide the "Press [E] to collect" prompt for whatever we're looking at.
	_update_prompt()

	# Press E to open/close a door you're looking at.
	if Input.is_action_just_pressed("interact"):
		_try_interact()

	# Lift us up onto any low stair step in front before the normal move.
	_try_step_up(delta)
	move_and_slide()

	# All the body sounds: footsteps, breathing, heartbeat.
	_update_audio(delta, sprinting)


# ---------------------------------------------------------------------------
# body sounds
# ---------------------------------------------------------------------------
func _update_audio(delta: float, sprinting: bool) -> void:
	# --- footsteps: one step for every stride-length of ground we cover ---
	var ground_speed: float = Vector3(velocity.x, 0.0, velocity.z).length()
	if is_on_floor() and ground_speed > 0.5:
		step_accum += ground_speed * delta
		# Sprinting takes longer strides but covers ground faster,
		# so the steps still come quicker.
		var stride: float = 2.0 if sprinting else 1.7
		if step_accum >= stride:
			step_accum = 0.0
			steps_audio.stream = step_sounds[randi() % step_sounds.size()]
			steps_audio.pitch_scale = randf_range(0.92, 1.08)
			# Running is louder than creeping.
			steps_audio.volume_db = -8.0 if sprinting else -13.0
			steps_audio.play()

	# --- how stressed are we? drives breathing and it's needed for the rest ---
	# Find the entity once (same trick the doors use).
	if entity == null or not is_instance_valid(entity):
		entity = get_tree().get_first_node_in_group("entity")
	var ent_dist: float = 999.0
	if entity != null:
		ent_dist = global_position.distance_to(entity.global_position)

	var tired: float = 1.0 - sprint_left / sprint_time        # 1 = out of breath
	var scared: float = clampf(1.0 - ent_dist / 15.0, 0.0, 1.0)  # 1 = it's ON us
	var stress: float = maxf(tired, scared)

	# --- breathing: always there faintly, faster and louder under stress ---
	breath_timer -= delta
	if breath_timer <= 0.0:
		# Calm = a soft breath every ~5 s. Panic = gasping every ~1.3 s.
		breath_timer = lerpf(5.0, 1.3, stress) + randf_range(-0.3, 0.3)
		breath_flip = not breath_flip
		# calm breaths normally; switch to the gasping sprint recording under stress
		var pool: Array = panic_breaths if stress > 0.55 else breath_sounds
		breath_audio.stream = pool[1 if breath_flip else 0]
		breath_audio.volume_db = lerpf(-26.0, -8.0, stress)
		breath_audio.pitch_scale = lerpf(0.97, 1.08, stress)  # real recordings: only a tiny pitch-up
		breath_audio.play()

	# --- heartbeat: kicks in when the entity is sprinting at us ---
	var chasing: bool = entity != null and entity.has_method("is_chasing") and entity.is_chasing()
	# Ramps up fast when the chase starts, fades out slowly after we escape.
	heart_level = move_toward(heart_level, 1.0 if chasing else 0.0,
			delta * (2.0 if chasing else 0.4))
	if heart_level > 0.05:
		heart_timer -= delta
		if heart_timer <= 0.0:
			# The closer it is, the faster the heart pounds (85 -> 160 bpm).
			var bpm: float = lerpf(85.0, 160.0, clampf(1.0 - ent_dist / 12.0, 0.0, 1.0))
			heart_timer = 60.0 / bpm
			heart_audio.volume_db = lerpf(-30.0, -5.0, heart_level)
			heart_audio.play()


# Fires a short ray from the camera. If it hits a page, we collect it.
# If it hits a door panel, we ask the door's hinge (its parent, which has
# door.gd on it) to open or close.
func _try_interact() -> void:
	var cam: Camera3D = $Head/Camera3D
	var from: Vector3 = cam.global_position
	var to: Vector3 = from - cam.global_transform.basis.z * 2.4  # 2.4 m reach
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var body: Node = hit.collider
	# A page on the wall? Grab it.
	if body.has_method("collect"):
		body.collect()
		return
	if body.get_parent() != null and body.get_parent().has_method("toggle"):
		body.get_parent().toggle()


# Shows the on-screen prompt when we're looking at something E works on
# (a page or a door within reach), and hides it the rest of the time.
# Uses the exact same ray as _try_interact, so the prompt never lies.
func _update_prompt() -> void:
	if prompt_label == null:
		return
	var cam: Camera3D = $Head/Camera3D
	var from: Vector3 = cam.global_position
	var to: Vector3 = from - cam.global_transform.basis.z * 2.4  # 2.4 m reach
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var text := ""
	if not hit.is_empty():
		var body: Node = hit.collider
		var parent: Node = body.get_parent()
		if body.has_method("collect"):
			text = "Press [E] to collect"
		elif parent != null and parent.has_method("toggle"):
			# Doors remember whether they're open (is_open lives in door.gd).
			text = "Press [E] to close" if parent.is_open else "Press [E] to open"
	prompt_label.text = text
	prompt_label.visible = text != ""


# If we're walking into a step no taller than step_height, rise onto it.
# This lets real stepped stairs work even though the controller can't
# auto-climb ledges on its own.
func _try_step_up(delta: float) -> void:
	# Only when standing on the ground and actually moving.
	if not is_on_floor():
		return
	var horiz: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if horiz.length() < 0.01:
		return

	# How far we're about to move this frame.
	var forward: Vector3 = horiz * delta

	# If nothing is blocking right in front, no step is needed.
	if not test_move(global_transform, forward):
		return

	# Blocked. Would the path be clear if we started one step higher?
	var lifted: Transform3D = global_transform.translated(Vector3(0, step_height, 0))
	if test_move(lifted, forward):
		return  # still blocked up there, so it's a real wall - don't climb

	# It's a low step: rise straight up onto it. move_and_slide then carries us
	# forward, and floor snapping settles us onto the step.
	move_and_collide(Vector3(0, step_height, 0))


# Draws the horror-styled stamina meter.
# fraction = 0..1 of stamina left. sprinting = are we running right now.
func _update_stamina_hud(fraction: float, sprinting: bool, delta: float) -> void:
	hud_time += delta

	# Shrink the bar to match how much stamina is left.
	stamina_fill.scale.x = fraction

	# Bar color goes from dim grey (full) to dark blood red (empty). Kept low-key.
	var bone: Color = Color(0.5, 0.5, 0.47)
	var blood: Color = Color(0.55, 0.06, 0.06)
	stamina_fill.color = blood.lerp(bone, fraction)
	stamina_fill.color.a = 0.72

	# Show the meter while sprinting or while it's not yet full; hide it when rested.
	var target_a: float = 1.0 if (sprinting or fraction < 0.999) else 0.0
	# Ease in/out so it fades instead of popping.
	hud_alpha = move_toward(hud_alpha, target_a, delta * 4.0)

	# When stamina is low, pulse the whole bar like a tired heartbeat.
	var shown: float = hud_alpha
	if fraction < 0.3:
		shown *= 0.7 + 0.3 * sin(hud_time * 10.0)
	stamina_track.modulate.a = shown


# Draws the camera battery meter (the small bar above stamina).
# Green when charged, blood red and blinking when nearly dead.
func _update_battery_hud() -> void:
	var frac: float = camcorder_node.battery_fraction()
	battery_fill.scale.x = frac
	var good := Color(0.45, 0.55, 0.4)
	var dead := Color(0.6, 0.08, 0.05)
	battery_fill.color = dead.lerp(good, frac)
	battery_fill.color.a = 0.72
	if frac < 0.2:
		# Blink so an almost-dead camera is impossible to miss.
		battery_track.modulate.a = 0.55 + 0.45 * maxf(sin(hud_time * 9.0), 0.0)
	else:
		battery_track.modulate.a = 0.85
