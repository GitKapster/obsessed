# Spawns the 5 collectible pages (Slender-style) and tracks the win.
#
# Every playthrough it shuffles the SPOTS list below, picks 5 that are far
# apart, and pins a page to the wall at each one. Collect all 5 to win.
# The spot list lives HERE (not in the map builder), so you can add/move
# spots without rebuilding the map.

extends Node3D

const PAGES_TO_WIN := 5
const MIN_SPACING := 18.0  # picked pages must be at least this far apart

# Camcorder batteries also spawn from the SPOTS list (on the floor below the
# wall spot, never at a spot a page took). Each one fully recharges the camera.
const BATTERY_COUNT := 6
const BATTERY_SPACING := 14.0

const MENU_SCENE := "res://addons/maaacks_menus_template/examples/scenes/menus/main_menu/main_menu_with_animations.tscn"

# Every place a page CAN appear: [position, facing angle in degrees].
# All spots sit on walls of corridors or rooms with a working way in, so
# every page is always reachable. Facing: 0 = page faces south (+Z),
# 90 = east (+X), 180 = north (-Z), -90 = west (-X).
# Page height: 1.5 (eye level) on floor 1, 5.6 on floor 2.
const SPOTS := [
	# --- floor 1 ---
	[Vector3(-18.0, 1.5, -37.33), 0.0],    # lobby, north wall
	[Vector3(15.0, 1.5, -25.17), 180.0],   # front corridor
	[Vector3(-25.0, 1.5, -13.83), 0.0],    # main spine corridor, west
	[Vector3(24.0, 1.5, -11.17), 180.0],   # main spine corridor, east
	[Vector3(-15.0, 1.5, 5.83), 180.0],    # middle corridor
	[Vector3(-20.0, 1.5, 20.17), 0.0],     # south corridor
	[Vector3(-37.83, 1.5, -16.0), 90.0],   # west corridor (V1)
	[Vector3(46.83, 1.5, 11.6), -90.0],    # ER corridor (V4)
	[Vector3(11.83, 1.5, -33.0), -90.0],   # chapel
	[Vector3(-24.0, 1.5, 19.83), 180.0],   # MRI room
	[Vector3(-16.0, 1.5, 37.33), 180.0],   # south room by the morgue
	[Vector3(51.0, 1.5, -37.33), 0.0],     # ER waiting
	[Vector3(21.0, 1.5, -37.33), 0.0],     # waiting area
	[Vector3(-54.83, 1.5, -33.0), 90.0],   # dining room
	# --- floor 2 ---
	[Vector3(-20.0, 5.6, -11.17), 180.0],  # F2 spine corridor
	[Vector3(26.0, 5.6, -25.17), 180.0],   # F2 north corridor
	[Vector3(-14.83, 5.6, -19.0), 90.0],   # nurse station
	[Vector3(12.0, 5.6, 22.83), 180.0],    # F2 south corridor
	[Vector3(-13.0, 5.6, 37.33), 180.0],   # F2 south patient room
	[Vector3(54.83, 5.6, -7.0), -90.0],    # ICU
]

var found := 0

var hud: CanvasLayer
var counter_label: Label
var counter_tween: Tween
var pickup_audio: AudioStreamPlayer
var icons: Array = []  # the 5 little page icons in the top-left

var page_script: Script = preload("res://scripts/page.gd")
var battery_script: Script = preload("res://scripts/battery.gd")

# Shared looks for all 5 pages.
var mat_paper: StandardMaterial3D
var mat_ink: StandardMaterial3D

# Shared looks for the batteries: dark body + a glowing stripe so they
# catch the eye in a dark room.
var mat_batt_body: StandardMaterial3D
var mat_batt_stripe: StandardMaterial3D

var battery_pickup_audio: AudioStreamPlayer


func _ready() -> void:
	_make_materials()
	_build_hud()

	# The pickup sound. Non-3D (it plays "in your hands"), and it keeps
	# playing even if the game pauses right after the last page.
	pickup_audio = AudioStreamPlayer.new()
	pickup_audio.stream = load("res://audio/page_pickup.res")
	pickup_audio.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pickup_audio)

	# Battery pickups make the camcorder's little motor click - reads as
	# "battery clicked into place".
	battery_pickup_audio = AudioStreamPlayer.new()
	battery_pickup_audio.stream = load("res://audio/cam_up.res")
	battery_pickup_audio.pitch_scale = 1.3
	add_child(battery_pickup_audio)

	# New random spots every playthrough.
	randomize()
	# Wait one physics frame so the walls exist before we raycast at them
	# (we check each spot isn't buried inside a wall).
	await get_tree().physics_frame
	var spawned := 0
	var page_spots: Array = _pick_spots()
	for spot in page_spots:
		_spawn_page(spot)
		spawned += 1
		print("PAGE %d spawned at %s" % [spawned, spot[0]])
	if spawned < PAGES_TO_WIN:
		push_error("PAGES: only %d of %d spawned!" % [spawned, PAGES_TO_WIN])

	# Batteries go at spots the pages didn't take.
	var batt_n := 0
	for spot in _pick_battery_spots(page_spots):
		_spawn_battery(spot)
		batt_n += 1
		print("BATTERY %d spawned at %s" % [batt_n, spot[0]])


func _make_materials() -> void:
	mat_paper = StandardMaterial3D.new()
	mat_paper.albedo_color = Color(0.93, 0.91, 0.85)
	mat_paper.roughness = 0.95
	# A faint glow so pages are spottable in the dark (like Slender's).
	mat_paper.emission_enabled = true
	mat_paper.emission = Color(0.55, 0.53, 0.48)
	mat_paper.emission_energy_multiplier = 0.35
	mat_ink = StandardMaterial3D.new()
	mat_ink.albedo_color = Color(0.12, 0.1, 0.1)
	mat_ink.roughness = 1.0

	mat_batt_body = StandardMaterial3D.new()
	mat_batt_body.albedo_color = Color(0.08, 0.08, 0.09)
	mat_batt_body.roughness = 0.5
	mat_batt_stripe = StandardMaterial3D.new()
	mat_batt_stripe.albedo_color = Color(0.3, 0.75, 0.4)
	mat_batt_stripe.emission_enabled = true
	mat_batt_stripe.emission = Color(0.25, 0.7, 0.35)
	mat_batt_stripe.emission_energy_multiplier = 0.8


# A spot is bad if the page would be buried inside a wall (a slightly-off
# coordinate). We fire a short ray out of the page's front face - if it
# hits a wall right away, the spot is buried.
func _spot_ok(spot: Array) -> bool:
	var pos: Vector3 = spot[0]
	var a: float = deg_to_rad(spot[1])
	var out := Vector3(sin(a), 0.0, cos(a))  # the way the page faces
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(pos + out * 0.03, pos + out * 0.5)
	query.collision_mask = 1  # walls only
	return space.intersect_ray(query).is_empty()


# Shuffle all spots, throw out any buried in a wall, then take 5 that are
# far apart from each other.
func _pick_spots() -> Array:
	var pool: Array = []
	for s in SPOTS:
		if _spot_ok(s):
			pool.append(s)
		else:
			push_warning("PAGES: spot %s is inside a wall - skipped" % s[0])
	pool.shuffle()
	var picked: Array = []
	for s in pool:
		if picked.size() >= PAGES_TO_WIN:
			break
		var far_enough := true
		for p in picked:
			if p[0].distance_to(s[0]) < MIN_SPACING:
				far_enough = false
				break
		if far_enough:
			picked.append(s)
	# Safety net: if the spacing rule filtered out too many, top up anyway.
	for s in pool:
		if picked.size() >= PAGES_TO_WIN:
			break
		if not picked.has(s):
			picked.append(s)
	return picked


# Pick spots for the batteries: anywhere in SPOTS that a page ISN'T,
# reasonably spread out across the building.
func _pick_battery_spots(page_spots: Array) -> Array:
	var pool: Array = []
	for s in SPOTS:
		if not page_spots.has(s):
			pool.append(s)
	pool.shuffle()
	var picked: Array = []
	for s in pool:
		if picked.size() >= BATTERY_COUNT:
			break
		var far_enough := true
		for p in picked:
			if p[0].distance_to(s[0]) < BATTERY_SPACING:
				far_enough = false
				break
		if far_enough:
			picked.append(s)
	return picked


# Builds one battery: a small dark block with a glowing stripe, sitting on
# the floor just out from the wall spot, at a careless angle.
func _spawn_battery(spot: Array) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Battery" + str(get_child_count())
	body.collision_layer = 2  # ignored by the navmesh, hit by the player's E-ray
	body.set_script(battery_script)

	var block := MeshInstance3D.new()
	var block_mesh := BoxMesh.new()
	block_mesh.size = Vector3(0.16, 0.07, 0.07)
	block_mesh.material = mat_batt_body
	block.mesh = block_mesh
	body.add_child(block)

	var stripe := MeshInstance3D.new()
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(0.05, 0.072, 0.072)
	stripe_mesh.material = mat_batt_stripe
	stripe.mesh = stripe_mesh
	stripe.position = Vector3(0.045, 0.0, 0.0)
	body.add_child(stripe)

	# A collision box bigger than the battery so it's easy to grab.
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.35, 0.3, 0.35)
	cs.shape = shape
	cs.position = Vector3(0, 0.1, 0)
	body.add_child(cs)

	# The spot is on a wall - drop to the floor and step out from the wall.
	var a: float = deg_to_rad(spot[1])
	var out := Vector3(sin(a), 0.0, cos(a))  # away from the wall
	var pos: Vector3 = spot[0] + out * 0.45
	pos.y = 4.15 if spot[0].y > 3.0 else 0.05  # floor 2 slab top / floor 1 ground
	body.position = pos
	body.rotation_degrees = Vector3(0, randf_range(0.0, 360.0), 0)
	body.connect("collected", _on_battery_collected)
	add_child(body)


func _on_battery_collected() -> void:
	# Refill the player's camcorder.
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null:
		var cam: Node = player.get_node_or_null("Head/Camera3D/Camcorder")
		if cam != null:
			cam.add_battery()
	battery_pickup_audio.play()

	# Flash "BATTERY REPLACED" using the same label the page counter uses.
	counter_label.text = "BATTERY REPLACED"
	if counter_tween:
		counter_tween.kill()
	counter_tween = create_tween()
	counter_tween.tween_property(counter_label, "modulate:a", 1.0, 0.15)
	counter_tween.tween_interval(1.6)
	counter_tween.tween_property(counter_label, "modulate:a", 0.0, 1.0)


# Builds one page: a thin white sheet with a few dark "scribble" lines,
# stuck to the wall, tilted a touch so it looks pinned up in a hurry.
func _spawn_page(spot: Array) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Page" + str(get_child_count())
	body.collision_layer = 2  # same layer as doors: ignored by the navmesh
	body.set_script(page_script)

	# The paper sheet.
	var sheet := MeshInstance3D.new()
	sheet.name = "Sheet"
	var sheet_mesh := BoxMesh.new()
	sheet_mesh.size = Vector3(0.24, 0.32, 0.012)
	sheet_mesh.material = mat_paper
	sheet.mesh = sheet_mesh
	body.add_child(sheet)

	# The scribbles: a few dark strips on the front face.
	for i in 4:
		var line := MeshInstance3D.new()
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(randf_range(0.12, 0.18), 0.016, 0.004)
		line_mesh.material = mat_ink
		line.mesh = line_mesh
		line.position = Vector3(randf_range(-0.02, 0.02), 0.1 - i * 0.055, 0.008)
		line.rotation.z = randf_range(-0.08, 0.08)
		body.add_child(line)

	# A collision box a little bigger than the paper, so the player's
	# E-ray hits it easily.
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3, 0.38, 0.05)
	cs.shape = shape
	body.add_child(cs)

	body.position = spot[0]
	body.rotation_degrees = Vector3(0, spot[1], randf_range(-4.0, 4.0))
	# (connect by name - the "collected" signal comes from the page script)
	body.connect("collected", _on_page_collected)
	add_child(body)


# ---------------------------------------------------------------- HUD

# One small paper icon for the top-left counter. It draws itself:
# a dim outline while the page is still out there, a filled sheet
# with scribble lines once you've collected it.
class PageIcon extends Control:
	var filled := false

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if filled:
			# Collected: solid paper + a few ink lines.
			draw_rect(r, Color(0.85, 0.83, 0.76, 0.9))
			for i in 4:
				var y := size.y * (0.25 + i * 0.17)
				draw_line(Vector2(size.x * 0.2, y), Vector2(size.x * 0.8, y),
						Color(0.12, 0.1, 0.1, 0.85), 1.5)
		else:
			# Not found yet: just a faint empty outline.
			draw_rect(r, Color(0.7, 0.68, 0.62, 0.28), false, 1.5)

	func fill() -> void:
		filled = true
		queue_redraw()
		# Little white flash so the pickup registers in the corner of your eye.
		modulate = Color(2.5, 2.5, 2.5)
		create_tween().tween_property(self, "modulate", Color.WHITE, 0.6)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "PageHUD"
	# Keeps working while the game is paused (needed for the win screen).
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)

	# "PAGE 2/5" - pops up on each pickup, then fades away.
	counter_label = Label.new()
	counter_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	counter_label.offset_bottom = -80
	counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	counter_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	counter_label.add_theme_font_size_override("font_size", 26)
	counter_label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	counter_label.modulate.a = 0.0
	hud.add_child(counter_label)

	# The 5 page icons, top-left corner, always visible.
	var row := HBoxContainer.new()
	row.position = Vector2(18, 18)
	row.add_theme_constant_override("separation", 8)
	hud.add_child(row)
	for i in PAGES_TO_WIN:
		var icon := PageIcon.new()
		icon.custom_minimum_size = Vector2(17, 23)  # small paper shape
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		icons.append(icon)


func _on_page_collected() -> void:
	found += 1
	pickup_audio.play()

	# Fill in the next icon in the top-left row.
	if found <= icons.size():
		icons[found - 1].fill()

	# Every page collected makes the entity 10% faster and angrier
	# (capped at +50% - see set_rage in entity.gd).
	get_tree().call_group("entity", "set_rage", found)

	# Show the counter, hold it, fade it out.
	counter_label.text = "PAGE %d/%d" % [found, PAGES_TO_WIN]
	if counter_tween:
		counter_tween.kill()
	counter_tween = create_tween()
	counter_tween.tween_property(counter_label, "modulate:a", 1.0, 0.15)
	counter_tween.tween_interval(2.2)
	counter_tween.tween_property(counter_label, "modulate:a", 0.0, 1.0)

	if found >= PAGES_TO_WIN:
		_win()


# All 5 collected: fade to black, show the win text, back to the main menu.
func _win() -> void:
	var black := ColorRect.new()
	black.color = Color(0, 0, 0)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.modulate.a = 0.0
	hud.add_child(black)

	var text := Label.new()
	text.text = "ALL %d PAGES COLLECTED\n\nyou escaped." % PAGES_TO_WIN
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 34)
	text.add_theme_color_override("font_color", Color(0.7, 0.67, 0.6))
	text.modulate.a = 0.0
	hud.add_child(text)

	# Freeze the game (this also frees the mouse - player.gd handles that).
	get_tree().paused = true

	# The tween must keep running while paused, hence TWEEN_PAUSE_PROCESS.
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(black, "modulate:a", 1.0, 1.4)
	tw.tween_property(text, "modulate:a", 1.0, 1.2)
	tw.tween_interval(3.5)
	tw.tween_callback(_go_to_menu)


func _go_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)
