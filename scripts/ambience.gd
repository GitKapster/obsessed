# Ambient sound for the abandoned hospital.
#
# Two layers:
#  1. A constant "bed" you always hear: deep building rumble + electrical
#     buzz from the dying fluorescent lights. Non-3D, always around you.
#  2. Random one-off noises out in the building - light flickers, metal
#     clanks, drips, distant creaks. Each one is a temporary 3D speaker
#     placed somewhere around the player, so they come from a real direction.
#
# This node lives inside player.tscn, so it exists whenever the player does.

extends Node

var room_audio: AudioStreamPlayer
var buzz_audio: AudioStreamPlayer
var industrial_audio: AudioStreamPlayer
var oneshots: Array = []           # the pool of random noises
var oneshot_timer: float = 8.0     # counts down to the next random noise

# The industrial hum cuts out now and then - the sudden silence is scarier
# than the sound. These track whether it's currently on and for how long.
const INDUSTRIAL_VOL := -16.0
var industrial_on: bool = true
var industrial_timer: float = 30.0  # counts down to the next on/off flip


func _ready() -> void:
	# Layer 1: the constant bed.
	room_audio = AudioStreamPlayer.new()
	room_audio.stream = load("res://audio/roomtone_loop.res")  # loops by itself
	room_audio.volume_db = -14.0
	add_child(room_audio)
	room_audio.play()

	buzz_audio = AudioStreamPlayer.new()
	buzz_audio.stream = load("res://audio/buzz_loop.res")  # loops by itself
	buzz_audio.volume_db = -24.0  # just barely there, like bad wiring
	add_child(buzz_audio)
	buzz_audio.play()

	# The industrial machine hum (real recording) - like something in the
	# building is still running. It drops out at random (see _process).
	industrial_audio = AudioStreamPlayer.new()
	industrial_audio.stream = load("res://audio/industrial_loop.res")  # loops by itself
	industrial_audio.volume_db = INDUSTRIAL_VOL
	add_child(industrial_audio)
	industrial_audio.play()

	# Layer 2: the pool of random building noises.
	# (drip is in twice so drips are a bit more common)
	# Note: the metallic "clank" sounds were removed - they read like an
	# elevator ting, which didn't fit.
	for n in ["flicker_1", "flicker_2", "creak_1", "creak_2",
			"drip", "drip"]:
		oneshots.append(load("res://audio/%s.res" % n))


func _process(delta: float) -> void:
	oneshot_timer -= delta
	if oneshot_timer <= 0.0:
		oneshot_timer = randf_range(7.0, 20.0)  # next noise in 7-20 seconds
		_play_distant_sound()

	# --- the industrial hum randomly dying and coming back ---
	industrial_timer -= delta
	if industrial_timer <= 0.0:
		industrial_on = not industrial_on
		# on for 25-60 s at a time, dead for 6-18 s
		industrial_timer = randf_range(25.0, 60.0) if industrial_on else randf_range(6.0, 18.0)
	# Cut out FAST (feels like something switched off), come back slowly.
	var target: float = INDUSTRIAL_VOL if industrial_on else -60.0
	var fade_speed: float = 8.0 if industrial_on else 55.0  # dB per second
	industrial_audio.volume_db = move_toward(industrial_audio.volume_db, target, fade_speed * delta)


# Put a temporary speaker at a random spot around the player, play one
# random noise through it, and have it clean itself up when done.
func _play_distant_sound() -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = oneshots[randi() % oneshots.size()]
	p.pitch_scale = randf_range(0.8, 1.1)
	p.max_distance = 45.0
	p.unit_size = 5.0
	p.volume_db = -3.0

	# Add it to the level (not the player, or it would move with us).
	var world: Node = get_tree().current_scene
	if world == null:
		world = get_parent()
	world.add_child(p)

	# Random direction, 8-25 m away, roughly head height or above.
	var ang: float = randf() * TAU
	var d: float = randf_range(8.0, 25.0)
	var base: Vector3 = get_parent().global_position
	p.global_position = base + Vector3(cos(ang) * d, randf_range(0.5, 3.0), sin(ang) * d)

	p.play()
	p.finished.connect(p.queue_free)  # delete itself once the sound ends
