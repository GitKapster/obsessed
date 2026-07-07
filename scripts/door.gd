# A working door.
#
# The scene tree is:  Door (this Node3D, the HINGE) -> Panel (StaticBody3D).
# The hinge sits on the door frame's edge, so rotating this node swings the
# door open like a real one.
#
# - The PLAYER opens/closes it by pressing E while looking at the panel
#   (player.gd calls toggle() on us).
# - The ENTITY can't turn handles - when it gets close to a closed door it
#   just SHOVES it open.
#
# The panel is on collision layer 2, which the navmesh bake ignores. That way
# a closed door still blocks the player, but never cuts a hole in the
# entity's navigation.
#
# IMPORTANT: the builder places hinges with different starting rotations
# (doors in north-south walls start at -90 deg, the second leaf of a double
# door is turned 180 deg). So we always swing RELATIVE to that starting
# rotation - never to an absolute angle, or the door spins into the wall.

extends Node3D

# How far the door swings, in degrees. Negative = swings the other way
# (used for the second leaf of double doors).
@export var open_angle: float = 105.0

var is_open: bool = false
var entity: Node3D = null   # found once, then remembered

# Remembered at startup (the door spawns closed):
var closed_y: float          # the hinge's rotation when the door is CLOSED
var closed_facing: Vector3   # which way the closed door faces (for the slam side test)

var swing_tween: Tween       # the one running swing - killed before starting a new one
var swing_target: float      # where the door is currently headed (so the slam doesn't re-fire every frame)

@onready var panel: StaticBody3D = $Panel

# The door's own speaker, plus its sounds (loaded once - Godot caches them,
# so 90 doors still share the same few sounds in memory).
var audio: AudioStreamPlayer3D
var creak_sounds: Array = []
var slam_sound: AudioStream


func _ready() -> void:
	# Remember the closed pose. Everything else is measured from here.
	closed_y = rotation.y
	closed_facing = global_transform.basis.z

	creak_sounds.append(load("res://audio/creak_1.res"))
	creak_sounds.append(load("res://audio/creak_2.res"))
	slam_sound = load("res://audio/door_slam.res")

	audio = AudioStreamPlayer3D.new()
	audio.max_distance = 25.0  # can't hear a door from further than this
	audio.unit_size = 4.0
	panel.add_child(audio)     # sits ON the panel, so the sound comes from the door

	swing_target = closed_y


# Starts (or restarts) the swing to a target angle. Killing the old tween
# first means a new swing always wins - no two tweens fighting over the door.
func _swing(target: float, seconds: float) -> void:
	swing_target = target
	if swing_tween and swing_tween.is_valid():
		swing_tween.kill()
	swing_tween = create_tween()
	swing_tween.tween_property(self, "rotation:y", target, seconds).set_trans(Tween.TRANS_SINE)


# Called by the player (E key). Swings the door open or closed.
func toggle() -> void:
	is_open = not is_open
	# Open = closed pose + open_angle. Closed = back to the closed pose.
	var target: float = closed_y + (deg_to_rad(open_angle) if is_open else 0.0)
	_swing(target, 0.35)

	# Old hinges creak every time. Random pick + pitch so they don't repeat.
	audio.stream = creak_sounds[randi() % creak_sounds.size()]
	audio.pitch_scale = randf_range(0.85, 1.15)
	audio.volume_db = -4.0
	audio.max_distance = 25.0  # quiet creak, normal range
	audio.unit_size = 4.0
	audio.play()


func _physics_process(_delta: float) -> void:
	# Find the entity once (it's in the "entity" group).
	if entity == null or not is_instance_valid(entity):
		entity = get_tree().get_first_node_in_group("entity")
		if entity == null:
			return

	# Entity near the door -> slam it out of its way, AWAY from it.
	# Works on closed doors and on doors left open toward it, so the
	# panel never ends up blocking its path. 2.2 m gives the swing time
	# to finish before the entity arrives, even at full sprint.
	if entity.global_position.distance_to(panel.global_position) < 2.2:
		# Which side of the door FRAME is the entity on? We test against the
		# closed facing, not the current one - an open door's own facing has
		# rotated with it and would give the wrong answer.
		var side: float = closed_facing.dot(entity.global_position - global_position)
		# Positive rotation swings the panel one way, negative the other -
		# always measured from the closed pose.
		var swing: float = deg_to_rad(absf(open_angle)) if side > 0.0 else -deg_to_rad(absf(open_angle))
		var target: float = closed_y + swing
		# Only slam if the door isn't already out of the way AND isn't
		# already mid-slam to that spot (otherwise this re-fires every frame).
		if absf(rotation.y - target) > 0.2 and absf(swing_target - target) > 0.01:
			is_open = true
			_swing(target, 0.12)
			# BANG - the entity shoved it. Loud warning the player can hear
			# anywhere within 20 m (unit_size keeps it loud over the range).
			audio.stream = slam_sound
			audio.pitch_scale = randf_range(0.95, 1.05)
			audio.volume_db = 4.0
			audio.max_distance = 20.0
			audio.unit_size = 10.0
			audio.play()
