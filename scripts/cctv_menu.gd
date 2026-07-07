# CCTV background for the main menu.
# Sits on a CanvasLayer at layer -1, so it draws BEHIND the menu buttons.
# Cycles through the security-camera stills in assets/ (made by
# tools/cctv_shots.tscn), with a burst of static between "cameras",
# plus the usual CCTV dressing: camera name, blinking REC, timestamp.

extends CanvasLayer

# [picture file, label shown top-left]
const SHOTS := [
	["cctv_lobby.png", "CAM 01  MAIN LOBBY"],
	["cctv_corridor.png", "CAM 02  CORRIDOR B"],
	["cctv_yard.png", "CAM 03  COURTYARD"],
]
const SWITCH_EVERY := 6.0   # seconds each camera stays on screen
const STATIC_TIME := 0.18   # how long the static burst lasts

var pics: Array = []        # the loaded pictures, same order as SHOTS
var screen: TextureRect     # the big background picture
var cam_label: Label
var time_label: Label
var rec_label: Label
var idx := 0                # which camera is showing
var switch_timer := SWITCH_EVERY
var blink := 0.0

@onready var mat := ShaderMaterial.new()


func _ready() -> void:
	layer = -1  # behind the menu

	# Menu theme music, looping. Loaded straight from disk (no import step),
	# and it dies with the menu scene, so the game itself stays music-free.
	var music_stream := AudioStreamWAV.load_from_file(
			"res://audio/music/801947__christmaskrumble666__on-dead-air.wav")
	if music_stream != null:
		music_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		music_stream.loop_begin = 0
		music_stream.loop_end = int(music_stream.get_length() * music_stream.mix_rate)
		var music := AudioStreamPlayer.new()
		music.stream = music_stream
		music.volume_db = -8.0
		add_child(music)
		music.play()

	# Load the stills straight from disk. (Image.load_from_file skips the
	# editor import step, so this works even for brand-new PNGs.)
	for s in SHOTS:
		var img := Image.load_from_file("res://assets/" + s[0])
		if img != null:
			pics.append(ImageTexture.create_from_image(img))
	if pics.is_empty():
		push_warning("CCTV: no stills found - run tools/cctv_shots.tscn")
		return

	mat.shader = load("res://shaders/cctv.gdshader")

	# The full-screen picture.
	screen = TextureRect.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	screen.texture = pics[0]
	screen.material = mat
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)

	# The text in the corners.
	cam_label = _corner_label(Control.PRESET_TOP_LEFT, Vector2(24, 18))
	cam_label.text = SHOTS[0][1]
	rec_label = _corner_label(Control.PRESET_TOP_RIGHT, Vector2(-110, 18))
	rec_label.text = "● REC"
	rec_label.add_theme_color_override("font_color", Color(0.85, 0.2, 0.15, 0.8))
	time_label = _corner_label(Control.PRESET_BOTTOM_RIGHT, Vector2(-250, -44))


# Small helper: one dim monospace-ish label pinned to a screen corner.
func _corner_label(preset: int, nudge: Vector2) -> Label:
	var l := Label.new()
	l.set_anchors_and_offsets_preset(preset)
	l.position += nudge
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.8, 0.85, 0.8, 0.65))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _process(delta: float) -> void:
	if pics.is_empty():
		return

	# Blinking REC dot (on 0.8 s, off 0.4 s).
	blink = fmod(blink + delta, 1.2)
	rec_label.visible = blink < 0.8

	# Ticking timestamp. Old date on purpose - the footage is "ancient".
	var t := Time.get_time_dict_from_system()
	time_label.text = "10-17-1996  %02d:%02d:%02d" % [t.hour, t.minute, t.second]

	# Time to switch cameras?
	switch_timer -= delta
	if switch_timer <= 0.0:
		switch_timer = SWITCH_EVERY + randf_range(-1.0, 1.0)
		_switch_camera()


# Burst of static, and while it covers the screen, swap the picture.
func _switch_camera() -> void:
	idx = (idx + 1) % pics.size()
	var tw := create_tween()
	tw.tween_method(_set_static, 0.0, 1.0, STATIC_TIME)
	tw.tween_callback(func () -> void:
		screen.texture = pics[idx]
		cam_label.text = SHOTS[idx][1])
	tw.tween_method(_set_static, 1.0, 0.0, STATIC_TIME)


func _set_static(v: float) -> void:
	mat.set_shader_parameter("static_amount", v)
