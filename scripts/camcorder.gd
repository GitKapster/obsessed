# Held camcorder with a flip-out LCD screen (Outlast style).
#
# How it works:
# - A second camera ("FeedCamera") sits inside a SubViewport and copies the
#   player's view every frame. That picture is shown on the camcorder's little
#   screen, where the VHS filter is applied. The rest of the world stays clean.
# - Key 1 = hold the flashlight, key 2 = hold the camcorder (always one or
#   the other). Right click raises/lowers the camcorder - only while held.
#   Filming drains the battery.
# - The REC dot, timestamp and focus brackets live ON the screen, not the whole view.
#
# This script lives on the "Camcorder" node inside player.tscn.

extends Node3D

# Where the camcorder sits when raised vs. lowered.
# Raised = screen pulled right up close and centred, so the feed is big and
#          clear. (The camcorder body hides the screen's far right edge, so
#          the BATT readout lives on the LEFT side of the feed, under REC.)
# Lowered = still held in view at the bottom, dropped and angled down like
#           you're carrying it.
# Stowed  = fully out of frame (used while the flashlight is in your hand).
@export var raised_position: Vector3 = Vector3(0.16, -0.02, -0.18)
@export var lowered_position: Vector3 = Vector3(0.24, -0.34, -0.5)
@export var stowed_position: Vector3 = Vector3(0.35, -0.75, -0.45)
@export var raised_rotation_deg: Vector3 = Vector3(0, 0, 0)
@export var lowered_rotation_deg: Vector3 = Vector3(-22, 14, 6)
@export var stowed_rotation_deg: Vector3 = Vector3(-50, 25, 15)

# Where the flashlight sits: in your hand, or dropped out of frame.
@export var light_held_position: Vector3 = Vector3(0.22, -0.22, -0.35)
@export var light_stowed_position: Vector3 = Vector3(0.3, -0.7, -0.45)
@export var light_held_rotation_deg: Vector3 = Vector3(0, -4, 8)
@export var light_stowed_rotation_deg: Vector3 = Vector3(-45, 20, 30)

# How fast the camcorder raises/lowers. Bigger = faster.
@export var raise_speed: float = 5.0

# --- battery ---
# Filming drains the battery. When it hits 0 the camera dies on the spot
# (screen black, auto-lowers) and won't come up again until the player finds
# a fresh battery lying around the hospital (full refill).
@export var battery_max: float = 40.0  # seconds of filming a full battery buys
var battery: float = battery_max

# Are we recording (camera up) or not (camera down)?
var recording: bool = false

# Is the flashlight the item in our hand right now?
# (Holding the flashlight stows the camcorder completely, and vice versa.)
var holding_light: bool = false

# 0 = fully lowered, 1 = fully raised.
var raise_amount: float = 0.0

# 0 = flashlight stowed, 1 = flashlight up in hand (drives its light too).
var flash_amount: float = 0.0

# Used to blink the REC dot.
var blink_timer: float = 0.0

# --- sound: the little motor/click when raising or lowering ---
# Non-3D speaker because the camcorder is in our own hands.
var audio: AudioStreamPlayer
var up_sound: AudioStream
var down_sound: AudioStream

# Screen UI lives inside the camera-feed SubViewport.
@onready var rec_label: Label = get_node("../../../CameraFeed/FeedUI/RecLabel")
@onready var time_label: Label = get_node("../../../CameraFeed/FeedUI/TimeLabel")
@onready var batt_label: Label = get_node("../../../CameraFeed/FeedUI/BattLabel")

# The flashlight (a visible torch model + its spot light) is our sibling
# under the player's camera. Only one item is ever in hand at a time.
@onready var flashlight_rig: Node3D = get_node("../FlashlightRig")
@onready var spot: SpotLight3D = get_node("../FlashlightRig/Spot")

# The torch beam's full strength (we fade it in/out with flash_amount).
# Strong on purpose: the world is very dark, the torch is how you SEE.
const LIGHT_ENERGY := 14.0

# The recording camera (in the SubViewport) and the real player camera.
@onready var feed_viewport: SubViewport = get_node("../../../CameraFeed")
@onready var feed_camera: Camera3D = get_node("../../../CameraFeed/FeedCamera")
@onready var main_camera: Camera3D = get_parent()  # the Camera3D this hangs from
@onready var flip_screen: MeshInstance3D = $FlipScreen


func _ready() -> void:
	# Start lowered.
	position = lowered_position
	rotation_degrees = lowered_rotation_deg
	raise_amount = 0.0
	# Use a narrower lens for the recording camera than the player's eye.
	# A smaller FOV "zooms in" the footage so it reads naturally on the small
	# screen instead of looking fish-eyed.
	feed_camera.fov = 55.0
	# Wire the live camera feed into the screen here in code. Doing it at runtime
	# (instead of in the scene file) is the reliable way to avoid a "missing
	# texture" pink screen.
	var screen_mat: ShaderMaterial = flip_screen.get_surface_override_material(0)
	if screen_mat:
		screen_mat.set_shader_parameter("feed_tex", feed_viewport.get_texture())

	# Build the speaker for the raise/lower sounds.
	up_sound = load("res://audio/cam_up.res")
	down_sound = load("res://audio/cam_down.res")
	audio = AudioStreamPlayer.new()
	audio.volume_db = -6.0
	add_child(audio)


func _unhandled_input(event: InputEvent) -> void:
	# 1 = flashlight, 2 = camcorder (pure item selects, nothing else).
	# Right click = raise/lower the camcorder, and ONLY that.
	if event.is_action_pressed("select_flashlight"):
		_select_flashlight()
	elif event.is_action_pressed("select_camera"):
		_select_camera()
	elif event.is_action_pressed("toggle_record"):
		_toggle_record()


# Key 1: put the camcorder away and take the flashlight out.
# Does nothing if the flashlight is already in hand.
func _select_flashlight() -> void:
	if holding_light:
		return
	holding_light = true
	recording = false  # camera can't stay up in a stowed pocket
	audio.stream = up_sound
	audio.pitch_scale = 1.6  # short high click = the torch switch
	audio.play()


# Key 2: put the flashlight away and CARRY the camcorder (lowered - it never
# raises on its own). Does nothing if the camcorder is already in hand.
func _select_camera() -> void:
	if not holding_light:
		return
	holding_light = false
	audio.stream = down_sound
	audio.pitch_scale = 1.6
	audio.play()


# Right click: raise/lower the camcorder. Only works while actually
# holding it - with the flashlight in hand this does nothing.
func _toggle_record() -> void:
	if holding_light:
		return
	if not recording and battery <= 0.0:
		# Dead battery - the camera just clunks and refuses to come up.
		audio.stream = down_sound
		audio.pitch_scale = 0.8
		audio.play()
		return
	recording = not recording
	# Rising whir when it comes up, falling whir + clunk when it drops.
	audio.stream = up_sound if recording else down_sound
	audio.pitch_scale = 1.0
	audio.play()


# Called by a battery pickup: fresh battery = full charge.
func add_battery() -> void:
	battery = battery_max


# 0..1, for the HUD bar in player.gd.
func battery_fraction() -> float:
	return battery / battery_max


func _process(delta: float) -> void:
	# Keep the recording camera pointed exactly where the player is looking.
	feed_camera.global_transform = main_camera.global_transform

	# --- battery drain while filming ---
	if recording:
		battery -= delta
		if battery <= 0.0:
			# Dead. The camera dies instantly and drops.
			battery = 0.0
			recording = false
			audio.stream = down_sound
			audio.pitch_scale = 0.8  # slightly lower = "powered down" clunk
			audio.play()

	# Move raise_amount toward its target (1 if recording, else 0).
	# (The entity checks this to know whether it's being filmed.)
	var target: float = 1.0 if recording else 0.0
	raise_amount = move_toward(raise_amount, target, delta * raise_speed)

	# --- the camcorder's three poses: raised / carried low / stowed away ---
	var cam_pos: Vector3 = lowered_position
	var cam_rot: Vector3 = lowered_rotation_deg
	if recording:
		cam_pos = raised_position
		cam_rot = raised_rotation_deg
	elif holding_light:
		# Flashlight in hand - the camcorder is put away completely.
		cam_pos = stowed_position
		cam_rot = stowed_rotation_deg
	var k: float = minf(1.0, delta * raise_speed)
	position = position.lerp(cam_pos, k)
	rotation_degrees = rotation_degrees.lerp(cam_rot, k)

	# --- the flashlight: comes up into the hand, beam fades in with it ---
	flash_amount = move_toward(flash_amount, 1.0 if holding_light else 0.0, delta * raise_speed)
	var light_pos: Vector3 = light_held_position if holding_light else light_stowed_position
	var light_rot: Vector3 = light_held_rotation_deg if holding_light else light_stowed_rotation_deg
	flashlight_rig.position = flashlight_rig.position.lerp(light_pos, k)
	flashlight_rig.rotation_degrees = flashlight_rig.rotation_degrees.lerp(light_rot, k)
	spot.light_energy = LIGHT_ENERGY * flash_amount
	spot.visible = flash_amount > 0.02

	# --- the screen is only lit while the camera is up AND has battery ---
	var screen_mat: ShaderMaterial = flip_screen.get_surface_override_material(0)
	if screen_mat:
		var on_amount: float = 0.0 if battery <= 0.0 else smoothstep(0.0, 1.0, raise_amount)
		screen_mat.set_shader_parameter("screen_on", on_amount)

	# Update the on-screen readouts. Blink REC once it's mostly raised.
	_update_timestamp()
	batt_label.text = "BATT %d%%" % int(round(battery_fraction() * 100.0))
	# The readout goes warning-red when the battery is nearly gone.
	batt_label.add_theme_color_override("font_color",
			Color(1.0, 0.25, 0.2) if battery_fraction() < 0.2 else Color(0.85, 0.85, 0.85))
	if raise_amount > 0.9:
		blink_timer += delta
		if blink_timer >= 0.5:
			blink_timer = 0.0
			rec_label.visible = not rec_label.visible
	else:
		rec_label.visible = true


# Found-footage style timestamp from the system clock.
func _update_timestamp() -> void:
	var t: Dictionary = Time.get_datetime_dict_from_system()
	time_label.text = "%04d-%02d-%02d  %02d:%02d:%02d" % [
		t.year, t.month, t.day, t.hour, t.minute, t.second
	]
