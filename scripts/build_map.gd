# Builds the whole abandoned-hospital greybox (2 floors) and SAVES it as
# main.tscn. You do NOT run this during the game - run tools/builder.tscn once
# whenever the layout data below changes; it rewrites main.tscn and quits.
#
# Map basics:
#  - Modelled on the real "Hospital Floor Plan Floor 1" drawing.
#  - North = -Z (the top of the drawing, Rock Prairie Road). X = east/west.
#  - Building is 110 m (X -55..55) by 75 m (Z -37.5..37.5).
#  - Floor 1 walls: y 0..4. Slab between floors: y 3.9..4.1.
#  - Floor 2 walls: y 4.1..8.1. Roof slab above that.
#
# Walls are data lines with "gaps" cut into them. Each gap = [center, width, kind]:
#   "door"   1.4 m doorway with a working door + header above it
#   "double" 2.8 m doorway with two door leaves + header
#   "open"   plain full-height opening (corridor mouths, big rooms)
#   "skip"   emit nothing here (a stairwell fills this spot itself)
#   "board"  boarded-up outside entrance (sealed dark gap + planks)

extends Node

const T := 0.3     # wall thickness
const H := 4.0     # wall height per floor
const Y2 := 4.1    # floor level of the second floor

var root: Node3D
var nav: NavigationRegion3D
var door_script: Script

# Shared materials so the whole map reuses a handful of them.
var mat_floor: StandardMaterial3D   # worn tile - floors
var mat_wall: StandardMaterial3D    # mossy plaster - walls
var mat_ceil: StandardMaterial3D    # granite tile - ceilings + roof
var mat_grass: StandardMaterial3D   # grass - courtyard
var mat_stair: StandardMaterial3D   # concrete - stairs/counters
var mat_dark: StandardMaterial3D
var mat_board: StandardMaterial3D
var mat_door: StandardMaterial3D
var mat_frame: StandardMaterial3D
var mat_fixture: StandardMaterial3D   # ceiling light housing (dark metal)
var mat_tube_on: StandardMaterial3D   # glowing fluorescent tube
var mat_tube_off: StandardMaterial3D  # dead grey tube

# Script for the flickering ceiling lights.
var flicker_script: Script = preload("res://scripts/flicker_light.gd")

# Caches so identical boxes share one mesh/shape resource (keeps the file small).
var mesh_cache := {}
var shape_cache := {}
var counters := {}


func _ready() -> void:
	door_script = load("res://scripts/door.gd")
	_make_materials()
	_build()
	_save()


# ---------------------------------------------------------------- materials

# The three main surfaces use full PBR texture sets (colour + normal +
# roughness maps) from the folders in assets/.
const TEX_WALL := "res://assets/worn_mossy_plasterwall_4k.blend/textures/worn_mossy_plasterwall_"
const TEX_FLOOR := "res://assets/worn_tile_floor_4k.blend/textures/worn_tile_floor_"
const TEX_CEIL := "res://assets/granite_tile_04_4k.blend/textures/granite_tile_04_"


func _make_materials() -> void:
	mat_wall = _pbr_mat(TEX_WALL, 0.33)    # worn mossy plaster, ~3 m per repeat
	mat_floor = _pbr_mat(TEX_FLOOR, 0.5)   # worn tile floor, ~2 m per repeat
	mat_ceil = _pbr_mat(TEX_CEIL, 0.5)     # granite tile, ~2 m per repeat
	# The smaller stuff uses the stylised pack + a tint colour on top.
	mat_grass = _tex_mat("res://assets/ld_textures_22.png", Color(0.75, 0.8, 0.7), 0.25)   # grass
	mat_stair = _tex_mat("res://assets/ld_textures_11.png", Color(0.75, 0.75, 0.77), 0.35) # concrete
	mat_board = _tex_mat("res://assets/ld_textures_21.png", Color(0.85, 0.8, 0.75), 0.5)   # old wood planks
	mat_frame = _tex_mat("res://assets/ld_textures_21.png", Color(0.5, 0.45, 0.4), 0.5)    # dark wood trim

	# Ceiling light fixture parts.
	mat_fixture = StandardMaterial3D.new()
	mat_fixture.albedo_color = Color(0.09, 0.09, 0.1)
	mat_fixture.roughness = 0.6
	mat_fixture.metallic = 0.3
	mat_tube_on = StandardMaterial3D.new()
	mat_tube_on.albedo_color = Color(0.8, 0.85, 0.75)
	mat_tube_on.emission_enabled = true
	mat_tube_on.emission = Color(0.7, 0.78, 0.62)
	mat_tube_on.emission_energy_multiplier = 1.6
	mat_tube_off = StandardMaterial3D.new()
	mat_tube_off.albedo_color = Color(0.32, 0.33, 0.3)  # dead tube, pale in torchlight
	mat_tube_off.roughness = 0.4
	mat_dark = _mat(Color(0.05, 0.05, 0.06))
	# Door leaves MOVE (they swing open), so no world-triplanar on them - the
	# texture would slide across the wood. Plain UV mapping instead.
	mat_door = StandardMaterial3D.new()
	mat_door.albedo_texture = load("res://assets/ld_textures_19.png")
	mat_door.albedo_color = Color(0.8, 0.72, 0.62)
	mat_door.roughness = 0.9


# A full PBR material: colour, normal (surface bumps) and roughness maps,
# wrapped around every box in world space (triplanar) so nothing needs UVs.
# The normal/roughness EXRs are optional: if the editor hasn't imported them
# yet, we skip them (colour still works) and say so in the output.
func _pbr_mat(prefix: String, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(prefix + "diff_4k.jpg")
	var nor := load(prefix + "nor_gl_4k.exr")
	if nor != null:
		m.normal_enabled = true
		m.normal_texture = nor
	else:
		print("NOTE: normal map not imported yet, skipped: ", prefix)
	var rough := load(prefix + "rough_4k.exr")
	if rough != null:
		m.roughness_texture = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	return m


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


# A textured material. "Triplanar" wraps the texture around boxes automatically
# (no UV work needed); "world" keeps the pattern lined up across neighbouring
# boxes so walls never show a seam. scale = texture repeats per metre.
func _tex_mat(path: String, tint: Color, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.albedo_color = tint
	m.roughness = 0.9
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	return m


# ---------------------------------------------------------------- small helpers

# Unique node names: Wall1, Wall2, Door1...
func nn(prefix: String) -> String:
	counters[prefix] = counters.get(prefix, 0) + 1
	return prefix + str(counters[prefix])


func _mesh(size: Vector3, mat: StandardMaterial3D) -> BoxMesh:
	var key := str(size) + str(mat.get_instance_id())
	if not mesh_cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		m.material = mat
		mesh_cache[key] = m
	return mesh_cache[key]


func _shape(size: Vector3) -> BoxShape3D:
	var key := str(size)
	if not shape_cache.has(key):
		var s := BoxShape3D.new()
		s.size = size
		shape_cache[key] = s
	return shape_cache[key]


# A solid box: mesh + collision, parented under Nav so the navmesh sees it.
func solid(prefix: String, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = nn(prefix)
	body.position = pos
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _mesh(size, mat)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = _shape(size)
	body.add_child(cs)
	nav.add_child(body)
	return body


# A visual-only box (no collision) - used for decorations like planks.
func visual(prefix: String, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nn(prefix)
	mi.mesh = _mesh(size, mat)
	mi.position = pos
	nav.add_child(mi)
	return mi


# A fluorescent ceiling light FIXTURE (visible housing + tube), stuck to the
# ceiling. state: "off" = dead dark tube (most of them), "on" = dim steady
# light, "flicker" = light + tube blink (scripts/flicker_light.gd).
# along_z = true rotates it for the north-south corridors.
func ceiling_light(x: float, y_ceil: float, z: float, state: String, along_z: bool = false) -> void:
	var fix := Node3D.new()
	fix.name = nn("CeilLight")
	fix.position = Vector3(x, y_ceil - 0.04, z)
	if along_z:
		fix.rotation_degrees.y = 90.0
	root.add_child(fix)

	var housing := MeshInstance3D.new()
	housing.name = "Housing"
	housing.mesh = _mesh(Vector3(1.25, 0.07, 0.28), mat_fixture)
	fix.add_child(housing)

	var tube := MeshInstance3D.new()
	tube.name = "Tube"
	tube.mesh = _mesh(Vector3(1.05, 0.03, 0.14),
			mat_tube_on if state != "off" else mat_tube_off)
	tube.position = Vector3(0, -0.05, 0)
	fix.add_child(tube)

	if state == "off":
		return
	var l := OmniLight3D.new()
	l.name = "Light"
	l.position = Vector3(0, -0.45, 0)
	l.light_color = Color(0.75, 0.8, 0.7)  # cold, slightly green fluorescent
	l.light_energy = 0.55
	l.omni_range = 8.0
	fix.add_child(l)
	if state == "flicker":
		fix.set_script(flicker_script)


# Random state for one fixture: most are dead, a few burn dimly, a few sputter.
func _light_state() -> String:
	var r := randf()
	if r < 0.62:
		return "off"
	if r < 0.85:
		return "on"
	return "flicker"


# A dim ceiling lamp.
func lamp(x: float, y: float, z: float) -> void:
	var l := OmniLight3D.new()
	l.name = nn("Lamp")
	l.position = Vector3(x, y, z)
	l.light_color = Color(0.85, 0.8, 0.7)
	l.light_energy = 0.16  # very dim - lamps are mood, not real light
	l.omni_range = 12.0
	root.add_child(l)


# ---------------------------------------------------------------- wall builders

# Wall running along X at depth z. gaps: [[center_x, width, kind], ...]
func hwall(z: float, x1: float, x2: float, y0: float, gaps: Array) -> void:
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(a, b): return a[0] < b[0])
	var cursor := x1
	for g in sorted:
		var g1: float = g[0] - g[1] * 0.5
		var g2: float = g[0] + g[1] * 0.5
		if g1 - cursor > 0.05:
			solid("Wall", Vector3(g1 - cursor, H, T), Vector3((cursor + g1) * 0.5, y0 + H * 0.5, z), mat_wall)
		_fill_gap(g, z, y0, true)
		cursor = g2
	if x2 - cursor > 0.05:
		solid("Wall", Vector3(x2 - cursor, H, T), Vector3((cursor + x2) * 0.5, y0 + H * 0.5, z), mat_wall)


# Wall running along Z at position x. gaps: [[center_z, width, kind], ...]
func vwall(x: float, z1: float, z2: float, y0: float, gaps: Array) -> void:
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(a, b): return a[0] < b[0])
	var cursor := z1
	for g in sorted:
		var g1: float = g[0] - g[1] * 0.5
		var g2: float = g[0] + g[1] * 0.5
		if g1 - cursor > 0.05:
			solid("Wall", Vector3(T, H, g1 - cursor), Vector3(x, y0 + H * 0.5, (cursor + g1) * 0.5), mat_wall)
		_fill_gap(g, x, y0, false)
		cursor = g2
	if z2 - cursor > 0.05:
		solid("Wall", Vector3(T, H, z2 - cursor), Vector3(x, y0 + H * 0.5, (cursor + z2) * 0.5), mat_wall)


# The corridor bands of the building (same on both floors).
# Used to decide which way doors swing: always AWAY from the corridor,
# INTO the room - so open doors never stick out into a corridor.
const EW_CORRIDORS := [[-28.0, -25.0], [-14.0, -11.0], [3.0, 6.0], [20.0, 23.0]]
const NS_CORRIDORS := [[-38.0, -35.0], [-1.5, 1.5], [32.0, 35.0], [44.0, 47.0]]


# Which side of this wall should a door swing to?
# Returns +1 (toward +Z for h-walls / +X for v-walls) or -1 (the other way).
# If the wall is the edge of a corridor, swing to the NON-corridor side.
# Room-to-room doors just keep the side they always had.
func _swing_side(along: float, horizontal: bool) -> float:
	var bands: Array = EW_CORRIDORS if horizontal else NS_CORRIDORS
	for b in bands:
		if absf(along - b[0]) < 0.2:
			return -1.0  # corridor sits on the + side of this wall
		if absf(along - b[1]) < 0.2:
			return 1.0   # corridor sits on the - side of this wall
	return -1.0 if horizontal else 1.0  # not a corridor wall: old default


# Puts whatever a gap needs (door, header, boards...) into the opening.
# "along" is the wall's fixed coordinate (z for h-walls, x for v-walls).
func _fill_gap(g: Array, along: float, y0: float, horizontal: bool) -> void:
	var g1: float = g[0] - g[1] * 0.5
	var g2: float = g[0] + g[1] * 0.5
	# Turn the swing side into a hinge angle. (For h-walls a POSITIVE angle
	# happens to swing toward -Z, for v-walls toward +X - hence the flip.)
	var side: float = _swing_side(along, horizontal)
	var ang: float = (-side if horizontal else side) * 105.0
	match g[2]:
		"door":
			_header(g[0], g[1], along, y0, horizontal)
			_frame(g1, g2, along, y0, horizontal)
			# Leaf width = the gap minus the two jambs (0.06 each) and a
			# small even clearance on both sides, so the door sits flush.
			_door(g1 + 0.08, along, y0, horizontal, false, ang, g[1] - 0.16)
		"double":
			_header(g[0], g[1], along, y0, horizontal)
			_frame(g1, g2, along, y0, horizontal)
			# Two leaves that meet neatly in the middle with a tiny gap.
			var leaf: float = g[1] * 0.5 - 0.09
			_door(g1 + 0.08, along, y0, horizontal, false, ang, leaf)
			_door(g2 - 0.08, along, y0, horizontal, true, -ang, leaf)
		"board":
			_boards(g[0], g[1], along, y0, horizontal)
		_:
			pass  # "open" and "skip": nothing to add


# The bit of wall above a doorway (from door height up to the ceiling).
func _header(c: float, w: float, along: float, y0: float, horizontal: bool) -> void:
	var size := Vector3(w, 1.8, T) if horizontal else Vector3(T, 1.8, w)
	var pos := Vector3(c, y0 + 3.1, along) if horizontal else Vector3(along, y0 + 3.1, c)
	solid("Header", size, pos, mat_wall)


# The trim around a doorway: two vertical jambs and a lintel across the top.
# Slightly deeper than the wall so it stands proud on both faces - makes the
# doorway read as a real framed opening instead of a raw hole in the wall.
# VISUAL ONLY (no collision): solid frames narrowed every doorway on the
# navmesh and the entity's pathfinding couldn't fit through - it would open
# a door and then refuse to walk in. The wall header still blocks for real.
func _frame(g1: float, g2: float, along: float, y0: float, horizontal: bool) -> void:
	var d := T + 0.08  # frame depth: pokes 0.04 out of each wall face
	# The two side jambs (floor up to the top of the opening).
	for edge in [g1 + 0.03, g2 - 0.03]:
		var size := Vector3(0.06, 2.2, d) if horizontal else Vector3(d, 2.2, 0.06)
		var pos := Vector3(edge, y0 + 1.1, along) if horizontal else Vector3(along, y0 + 1.1, edge)
		visual("Jamb", size, pos, mat_frame)
	# The lintel (top piece), tucked under the header.
	var lsize := Vector3(g2 - g1, 0.06, d) if horizontal else Vector3(d, 0.06, g2 - g1)
	var lpos := Vector3((g1 + g2) * 0.5, y0 + 2.17, along) if horizontal else Vector3(along, y0 + 2.17, (g1 + g2) * 0.5)
	visual("Lintel", lsize, lpos, mat_frame)


# One door leaf. "hinge_at" is where the hinge sits along the wall.
# flipped = hinged on the far side (second leaf of a double door).
# leaf = how wide this door panel is (sized to fill the frame evenly).
func _door(hinge_at: float, along: float, y0: float, horizontal: bool, flipped: bool, angle: float, leaf: float) -> void:
	var hinge := Node3D.new()
	hinge.name = nn("Door")
	hinge.set_script(door_script)
	hinge.set("open_angle", angle)
	hinge.add_to_group("door", true)

	var rot := 0.0 if horizontal else -PI * 0.5
	if flipped:
		rot += PI
	hinge.position = Vector3(hinge_at, y0, along) if horizontal else Vector3(along, y0, hinge_at)
	hinge.rotation = Vector3(0, rot, 0)

	# Panel height 2.11: fits under the lintel (2.14) with a whisker of air,
	# and floats 0.015 off the floor so it never scrapes.
	var panel := StaticBody3D.new()
	panel.name = "Panel"
	panel.collision_layer = 2      # layer 2 = ignored by the navmesh bake
	panel.position = Vector3(leaf * 0.5, 1.07, 0)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _mesh(Vector3(leaf, 2.11, 0.09), mat_door)
	panel.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = _shape(Vector3(leaf, 2.11, 0.09))
	panel.add_child(cs)
	# A small dark handle bar near the free edge (visual only).
	var handle := MeshInstance3D.new()
	handle.name = "Handle"
	handle.mesh = _mesh(Vector3(0.05, 0.05, 0.22), mat_dark)
	handle.position = Vector3(leaf * 0.5 - 0.14, -0.05, 0)
	panel.add_child(handle)
	hinge.add_child(panel)
	nav.add_child(hinge)


# A boarded-up outside entrance: a dark sealed slab plus a few planks.
func _boards(c: float, w: float, along: float, y0: float, horizontal: bool) -> void:
	# Which way is "inside the building"? Toward the origin.
	var side := 1.0 if along < 0.0 else -1.0
	# The dark seal (has collision, so nobody walks out into the void).
	var seal_size := Vector3(w, H, 0.14) if horizontal else Vector3(0.14, H, w)
	var seal_pos := Vector3(c, y0 + H * 0.5, along) if horizontal else Vector3(along, y0 + H * 0.5, c)
	solid("Boarded", seal_size, seal_pos, mat_dark)
	# Planks nailed across the inside face.
	var heights := [0.8, 1.7, 2.7]
	for i in heights.size():
		var y: float = y0 + heights[i]
		var plank: MeshInstance3D
		if horizontal:
			plank = visual("Plank", Vector3(w + 0.5, 0.35, 0.08), Vector3(c, y, along + side * 0.22), mat_board)
			plank.rotation.z = 0.05 if i % 2 == 0 else -0.06
		else:
			plank = visual("Plank", Vector3(0.08, 0.35, w + 0.5), Vector3(along + side * 0.22, y, c), mat_board)
			plank.rotation.x = 0.05 if i % 2 == 0 else -0.06


# ---------------------------------------------------------------- stairwell

# An invisible sloped collider laid over a stair flight, so walking up feels
# like a smooth glide instead of bumping up every step. The steps themselves
# are visual-only now. "a" is the bottom of the slope, "b" the top.
func ramp(a: Vector3, b: Vector3, width: float) -> void:
	var body := StaticBody3D.new()
	body.name = nn("StairRamp")
	# Aim the box along the slope, then sink it half its thickness down,
	# so its TOP surface lies exactly along the a->b line.
	var bas := Basis.looking_at(b - a, Vector3.UP)
	body.basis = bas
	body.position = (a + b) * 0.5 - bas.y * 0.15
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = _shape(Vector3(width, 0.3, a.distance_to(b)))
	body.add_child(cs)
	nav.add_child(body)


# A switchback (U-turn) stairwell filling x ox..ox+6, z oz..oz+7.
# Entry door AND upstairs exit are both on the NORTH wall (z = oz), so both
# floors connect to the same corridor. Flight A (west) climbs south to a
# half-way landing, flight B (east) climbs back north and exits upstairs.
func stairwell(ox: float, oz: float) -> void:
	var ax := ox + 1.3   # centre of flight A (west)
	var bx := ox + 4.7   # centre of flight B (east)

	# Flight A: 10 steps, entry side (north) up to the landing.
	# The steps are just visuals - the invisible ramp below does the collision.
	for i in 10:
		var top := 0.205 * (i + 1)
		visual("Step", Vector3(2.4, 0.4, 0.3), Vector3(ax, top - 0.2, oz + 2.65 + 0.3 * i), mat_stair)
	# Half-way landing across the south end (a little longer than before, so
	# it also covers the top step of each flight - those lost their collision).
	solid("Landing", Vector3(5.8, 0.4, 1.7), Vector3(ox + 3.0, 1.85, oz + 6.05), mat_stair)
	# Flight B: 10 more steps, landing back up to the north exit at y 4.1.
	for i in 10:
		var top := 2.05 + 0.205 * (i + 1)
		visual("Step", Vector3(2.4, 0.4, 0.3), Vector3(bx, top - 0.2, oz + 5.35 - 0.3 * i), mat_stair)

	# The two invisible ramps. Their tops run along the step NOSE line, so
	# your feet track the visible steps while the walk stays silky.
	ramp(Vector3(ax, 0.0, oz + 2.2), Vector3(ax, 2.05, oz + 5.2), 2.4)   # floor -> landing
	ramp(Vector3(bx, 2.05, oz + 5.5), Vector3(bx, 4.1, oz + 2.5), 2.4)  # landing -> floor 2

	# Spine wall between the two flights (like a real stairwell core).
	solid("StairSpine", Vector3(0.6, 5.3, 3.0), Vector3(ox + 3.0, 2.65, oz + 4.0), mat_wall)
	# Railing upstairs so you can't walk off the edge into the stair hole.
	solid("Rail", Vector3(3.5, 1.1, 0.15), Vector3(ox + 1.75, Y2 + 0.55, oz + 2.5), mat_wall)

	# North wall: ground floor has the entry door (west half),
	# second floor has the open exit (east half).
	hwall(oz, ox, ox + 6, 0.0, [[ax, 1.4, "door"]])
	hwall(oz, ox, ox + 6, Y2, [[bx, 2.2, "open"]])

	# Lamps inside the shaft, one per floor.
	lamp(ox + 3.0, 3.3, oz + 3.5)
	lamp(ox + 3.0, 7.4, oz + 3.5)

	# Navigation links so the entity ALWAYS knows the stairs connect the
	# floors, even if the baked navmesh over the ramps has seams.
	# One link per flight, laid EXACTLY along its ramp - the entity walks
	# the link like a slope, tracking the steps, so it can't clip the slab.
	# (The old single link cut diagonally across the shaft - that's what
	# made it fly/clip through the floor.)
	var link_a := NavigationLink3D.new()
	link_a.name = nn("StairLinkA")
	link_a.start_position = Vector3(ax, 0.05, oz + 2.2)   # bottom of flight A
	link_a.end_position = Vector3(ax, 2.1, oz + 5.2)      # top of flight A (landing)
	nav.add_child(link_a)
	var link_b := NavigationLink3D.new()
	link_b.name = nn("StairLinkB")
	link_b.start_position = Vector3(bx, 2.1, oz + 5.5)    # landing, base of flight B
	link_b.end_position = Vector3(bx, Y2 + 0.05, oz + 2.5) # top of flight B (floor 2)
	nav.add_child(link_b)


# Dead elevator doors: two dark sealed panels on the corridor-facing wall.
func elevators(x1: float, x2: float, zwall: float) -> void:
	for fy in [0.0, Y2]:
		for px in [x1 + 1.8, x2 - 1.8]:
			visual("ElevDoor", Vector3(1.3, 2.6, 0.1), Vector3(px, fy + 1.4, zwall - T * 0.5 - 0.06), mat_dark)


# A reception/nurse counter (a simple desk-height block).
func counter(x: float, z: float, w: float, y0: float) -> void:
	solid("Counter", Vector3(w, 1.05, 0.7), Vector3(x, y0 + 0.525, z), mat_stair)


# ---------------------------------------------------------------- the layout

func _build() -> void:
	root = Node3D.new()
	root.name = "Main"

	# Dark, foggy horror environment (same look as before).
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.012)
	env.ambient_light_color = Color(0.05, 0.05, 0.06)
	# Very low on purpose - the dark itself limits how far you can see;
	# the flashlight / camcorder night vision are how you see further.
	env.ambient_light_energy = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	# Fog is BLACK, so distance reads as pure darkness (not a grey haze) -
	# far ends of corridors just swallow into nothing.
	env.fog_light_color = Color(0.008, 0.008, 0.01)
	env.fog_density = 0.026
	we.environment = env
	root.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.name = "MoonLight"
	moon.rotation_degrees = Vector3(-55, 35, 0)
	moon.light_color = Color(0.6, 0.65, 0.8)
	moon.light_energy = 0.04  # barely-there moonlight
	root.add_child(moon)

	# Everything solid goes under Nav so the navmesh bakes over it.
	nav = NavigationRegion3D.new()
	nav.name = "Nav"
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1   # layer 1 only -> door panels (layer 2) never block it
	# Kept SMALL on purpose: the bake rounds these UP to whole voxels
	# (0.25 m), so bigger values silently pinch doorways shut. 1.5 and
	# 0.25 are exact voxel sizes - doorways stay comfortably walkable.
	nm.agent_height = 1.5
	nm.agent_radius = 0.25
	nm.agent_max_climb = 0.4
	nav.navigation_mesh = nm
	nav.set_script(load("res://scripts/nav_baker.gd"))
	root.add_child(nav)

	_slabs()
	_floor1()
	_floor2()

	# Two stairwell cores (positions match the plan: central + southwest).
	stairwell(1.5, -11.0)
	stairwell(-53.0, 23.0)
	# Dead elevators next to each stairwell.
	elevators(7.5, 13.5, -11.0)
	elevators(-47.0, -41.0, 23.0)

	# Courtyard: a cool blue "moonlight pool" so the grass reads as outdoors
	# under the open sky (the warm lamp() lights would look wrong here).
	var moonpool := OmniLight3D.new()
	moonpool.name = "CourtyardLight"
	moonpool.position = Vector3(19, 5.0, -0.5)
	moonpool.light_color = Color(0.55, 0.62, 0.8)
	moonpool.light_energy = 0.7
	moonpool.omni_range = 16.0
	root.add_child(moonpool)

	_lights()

	# Player spawns in the lobby just inside the boarded main entrance,
	# facing south into the hospital.
	var player = load("res://scenes/player.tscn").instantiate()
	player.name = "Player"
	player.position = Vector3(-11, 0.3, -33.8)
	player.rotation = Vector3(0, PI, 0)
	root.add_child(player)

	# Entity starts in the old ambulance bay, the far south-east corner.
	var entity = load("res://scenes/entity.tscn").instantiate()
	entity.name = "Entity"
	entity.position = Vector3(48, 0.1, 30)
	root.add_child(entity)

	# Spawns the 5 collectible pages at random wall spots each playthrough
	# (the spot list lives in the script, so no rebuild needed to change it).
	var pages := Node3D.new()
	pages.name = "PageManager"
	pages.set_script(load("res://scripts/page_manager.gd"))
	root.add_child(pages)

	# Fills the rooms with furniture props at level start (the placement
	# list lives in the script, so no rebuild needed to move things).
	var props := Node3D.new()
	props.name = "PropSpawner"
	props.set_script(load("res://scripts/prop_spawner.gd"))
	root.add_child(props)


# One piece of the between-floors slab: tile on top (floor 2's flooring) plus
# a thin granite panel glued underneath (floor 1's ceiling). Two layers so the
# floor texture never bleeds into the ceiling below.
func slab(sx: float, sz: float, x: float, z: float) -> void:
	solid("Slab", Vector3(sx, 0.2, sz), Vector3(x, 4.0, z), mat_floor)
	visual("Ceil", Vector3(sx, 0.04, sz), Vector3(x, 3.88, z), mat_ceil)


# Ground slab, the between-floors slab (with holes), and the roof.
func _slabs() -> void:
	# Ground floor (tiles), plus a grass patch where the courtyard is.
	# The grass sits 1 cm above the tiles so the two never flicker.
	solid("Ground", Vector3(112, 0.2, 77), Vector3(0, -0.1, 0), mat_floor)
	solid("CourtGrass", Vector3(10, 0.2, 7), Vector3(19, -0.09, -0.5), mat_grass)
	# Between-floors slab, laid as strips that leave three holes open:
	# Hole 1 (central stairs): x 1.5..7.5, z -8.5..-4.
	# Hole 2 (southwest stairs): x -53..-47, z 25.5..30.
	# Hole 3 (COURTYARD, open to the sky): x 14..24, z -4..3.
	slab(110, 29, 0, -23.0)          # z -37.5..-8.5
	slab(56.5, 4.5, -26.75, -6.25)   # z -8.5..-4, west of hole 1
	slab(47.5, 4.5, 31.25, -6.25)    # z -8.5..-4, east of hole 1
	slab(69, 7, -20.5, -0.5)         # z -4..3, west of the courtyard
	slab(31, 7, 39.5, -0.5)          # z -4..3, east of the courtyard
	slab(110, 22.5, 0, 14.25)        # z 3..25.5
	slab(2, 4.5, -54.0, 27.75)       # z 25.5..30, west of hole 2
	slab(102, 4.5, 4.0, 27.75)       # z 25.5..30, east of hole 2
	slab(110, 7.5, 0, 33.75)         # z 30..37.5
	# Roof in granite: its underside doubles as floor 2's ceiling.
	# Four pieces that leave the courtyard shaft open to the sky.
	solid("Roof", Vector3(110.6, 0.2, 33.8), Vector3(0, 8.2, -20.9), mat_ceil)   # north of courtyard
	solid("Roof", Vector3(110.6, 0.2, 34.8), Vector3(0, 8.2, 20.4), mat_ceil)    # south of courtyard
	solid("Roof", Vector3(69.3, 0.2, 7), Vector3(-20.65, 8.2, -0.5), mat_ceil)   # west of courtyard
	solid("Roof", Vector3(31.3, 0.2, 7), Vector3(39.65, 8.2, -0.5), mat_ceil)    # east of courtyard


# ------------------------------------------------ FLOOR 1 (from the blueprint)
#
# North band:  Dining | Gift Shop | Restrooms | LOBBY(entrance) | Chapel | Waiting | ER Reg | ER Waiting
# Corridors:   4 east-west corridors (z -28..-25, -14..-11, 3..6, 20..23)
#              + 4 north-south corridors (V1 x-38..-35, V2 x-1.5..1.5, V3 x32..35, V4 x44..47)
# Middle:      Registration, offices, Ultrasound, EKG, X-Ray, Nuclear Medicine,
#              central stairs+elevators, ER fast track, ER bay
# South:       MRI, hot lab, wards, ER rooms 10-15 (east edge), morgue,
#              boiler, laundry, ambulance bay, SW stairs+elevators
func _floor1() -> void:
	var y := 0.0

	# --- east-west wall lines (north to south) ---
	hwall(-37.5, -55, 55, y, [[-11, 6, "board"], [47.5, 3, "board"]])  # north perimeter: main + patient entrances
	hwall(-28, -55, 55, y, [[-47, 1.4, "door"], [-35.5, 1.4, "door"], [-26, 1.4, "door"], [-8.75, 20.5, "open"], [7.5, 1.4, "door"], [21, 14, "open"], [35, 6, "open"], [47, 6, "open"]])
	hwall(-25, -55, 55, y, [[-46, 1.4, "door"], [-36.5, 3, "open"], [-30, 1.4, "door"], [-20, 1.4, "door"], [-8.25, 11.5, "open"], [0, 3, "open"], [8, 1.4, "door"], [19, 1.4, "door"], [28, 1.4, "door"], [33.5, 3, "open"], [39.5, 4, "open"], [45.5, 3, "open"], [51, 3, "open"]])
	hwall(-14, -55, 55, y, [[-36.5, 3, "open"], [-8, 2.8, "double"], [0, 3, "open"], [33.5, 3, "open"], [39.5, 3, "open"], [45.5, 3, "open"]])
	hwall(-11, -55, 55, y, [[-46, 1.4, "door"], [-36.5, 3, "open"], [-26.5, 1.4, "door"], [-14, 1.4, "door"], [-6, 1.4, "door"], [0, 3, "open"], [4.5, 6, "skip"], [19, 1.4, "door"], [28, 1.4, "door"], [33.5, 3, "open"], [39.5, 4, "open"], [45.5, 3, "open"], [51, 3, "open"]])
	hwall(-4, -38, 55, y, [[-36.5, 3, "open"], [-27, 1.4, "door"], [0, 3, "open"], [19, 1.4, "door"], [33.5, 3, "open"], [39.5, 3, "open"], [45.5, 3, "open"], [51, 3, "open"]])
	hwall(3, -55, 55, y, [[-27.5, 1.4, "door"], [-10, 1.4, "door"], [0, 3, "open"], [7.5, 1.4, "door"], [19, 1.4, "door"], [28, 1.4, "door"], [33.5, 3, "open"], [39.5, 4, "open"], [45.5, 3, "open"], [51, 3, "open"]])
	hwall(6, -55, 55, y, [[-46, 1.4, "door"], [-36.5, 3, "open"], [-24, 2.8, "double"], [-8, 1.4, "door"], [0, 3, "open"], [9, 1.4, "door"], [24, 1.4, "door"], [33.5, 3, "open"], [39.5, 3, "open"], [45.5, 3, "open"]])
	hwall(13, -14, 47, y, [[-8, 1.4, "door"], [0, 3, "open"], [9, 1.4, "door"], [24, 1.4, "door"], [33.5, 3, "open"], [39.5, 3, "open"], [45.5, 3, "open"]])
	hwall(20, -55, 47, y, [[-36.5, 3, "open"], [-8, 1.4, "door"], [0, 3, "open"], [9, 1.4, "door"], [24, 1.4, "door"], [33.5, 3, "open"], [39.5, 3, "open"], [45.5, 3, "open"]])
	hwall(23, -55, 55, y, [[-50, 6, "skip"], [-32, 1.4, "door"], [-16, 1.4, "door"], [0, 1.4, "door"], [16, 1.4, "door"], [32, 1.4, "door"], [45.5, 3, "open"]])
	hwall(37.5, -55, 55, y, [[47, 4, "board"]])  # south perimeter: boarded ambulance door
	hwall(30, -55, -41, y, [])                   # behind SW stairs + elevators
	hwall(-35.5, -14, -8, y, [[-11, 2.8, "double"]])  # lobby vestibule inner double doors
	# ER rooms 10-15 dividers (east edge).
	for dz in [8.833, 11.667, 14.5, 17.333, 20.167]:
		hwall(dz, 47, 55, y, [])

	# --- north-south walls ---
	vwall(-55, -37.5, 37.5, y, [])                       # west perimeter
	vwall(55, -37.5, 37.5, y, [[-31.5, 3, "board"]])     # east perimeter, boarded ER entrance
	# North band dividers.
	for dx in [-40, -31, -21, 3, 12, 30]:
		vwall(dx, -37.5, -28, y, [])
	vwall(40, -37.5, -28, y, [[-33, 1.4, "door"]])       # ER Reg <-> ER Waiting
	vwall(-14, -37.5, -35.5, y, [])                      # vestibule sides
	vwall(-8, -37.5, -35.5, y, [])
	# Registration/office band dividers.
	vwall(-38, -25, -14, y, [[-19.5, 1.4, "door"]])      # serving area side door onto V1
	for dx in [-35, -25, -15, -1.5, 1.5, 14, 24, 32, 35, 44]:
		vwall(dx, -25, -14, y, [])
	vwall(47, -25, -14, y, [[-19.5, 1.4, "door"]])       # triage door onto V4
	# Imaging band dividers.
	vwall(-38, -11, 3, y, [[-4, 1.4, "door"]])           # physician dining onto V1
	vwall(-35, -11, 3, y, [])
	for dx in [-18, -10, -1.5, 1.5, 7.5, 13.5, 24]:
		vwall(dx, -11, -4, y, [])
	for dx in [-20, -1.5, 1.5, 14, 24]:
		vwall(dx, -4, 3, y, [])
	for dx in [32, 35, 44]:
		vwall(dx, -11, 3, y, [])
	vwall(47, -11, 3, y, [[-4, 2, "open"]])              # ER east bay onto V4
	# MRI band dividers.
	vwall(-38, 6, 20, y, [])
	vwall(-35, 6, 20, y, [])
	vwall(-14, 6, 20, y, [[9, 1.4, "door"]])             # MRI <-> control room
	for dx in [-1.5, 1.5, 16, 32, 35]:
		vwall(dx, 6, 20, y, [])
	vwall(44, 6, 20, y, [])
	# ER rooms 10-15: doors off the V4 corridor.
	vwall(47, 6, 23, y, [[7.417, 1.4, "door"], [10.25, 1.4, "door"], [13.083, 1.4, "door"], [15.917, 1.4, "door"], [18.75, 1.4, "door"], [21.583, 1.4, "door"]])
	# South band dividers.
	for dx in [-53, -47, -41]:
		vwall(dx, 23, 30, y, [])
	for dx in [-24, -8, 8, 24, 40]:
		vwall(dx, 23, 37.5, y, [])

	# Front desks.
	counter(-11, -30.5, 5, y)      # lobby reception
	counter(-8.25, -19.5, 7, y)    # main patient registration
	counter(35, -31.0, 4, y)       # ER registration


# ------------------------------------------------ FLOOR 2 (ward floor)
#
# Same corridor grid as downstairs so the building hangs together:
# patient rooms along the north and south edges, nurse station in the middle,
# operating theatres above imaging, ICU east, physio hall above the MRI.
func _floor2() -> void:
	var y := Y2

	hwall(-37.5, -55, 55, y, [])
	hwall(-28, -55, 55, y, [[-49.5, 1.4, "door"], [-38.5, 1.4, "door"], [-27.5, 1.4, "door"], [-16.5, 1.4, "door"], [-6.25, 1.4, "door"], [0, 3, "open"], [6.25, 1.4, "door"], [16.5, 1.4, "door"], [27.5, 1.4, "door"], [38.5, 1.4, "door"], [49.5, 1.4, "door"]])
	hwall(-25, -55, 55, y, [[-46, 1.4, "door"], [-36.5, 3, "open"], [-25, 6, "open"], [-8.25, 11.5, "open"], [0, 3, "open"], [8.25, 11.5, "open"], [23, 1.4, "door"], [33.5, 3, "open"], [39.5, 1.4, "door"], [45.5, 3, "open"], [51, 1.4, "door"]])
	hwall(-14, -55, 55, y, [[-36.5, 3, "open"], [0, 3, "open"], [33.5, 3, "open"], [45.5, 3, "open"]])
	hwall(-11, -55, 55, y, [[-46, 1.4, "door"], [-36.5, 3, "open"], [-26.5, 1.4, "door"], [-10, 1.4, "door"], [0, 3, "open"], [4.5, 6, "skip"], [19, 1.4, "door"], [28, 1.4, "door"], [33.5, 3, "open"], [39.5, 4, "open"], [45.5, 3, "open"]])
	# No doors at x 19 up here - they'd open straight into the courtyard shaft.
	hwall(-4, -38, 55, y, [[-36.5, 3, "open"], [-27, 1.4, "door"], [0, 3, "open"], [33.5, 3, "open"], [39.5, 3, "open"], [45.5, 3, "open"], [51, 1.4, "door"]])
	hwall(3, -55, 55, y, [[-27.5, 1.4, "door"], [-10, 1.4, "door"], [0, 3, "open"], [7.5, 1.4, "door"], [28, 1.4, "door"], [33.5, 3, "open"], [39.5, 4, "open"], [45.5, 3, "open"], [51, 3, "open"]])
	hwall(6, -55, 55, y, [[-46, 1.4, "door"], [-36.5, 3, "open"], [-24, 4, "open"], [-8, 1.4, "door"], [0, 3, "open"], [9, 1.4, "door"], [24, 1.4, "door"], [33.5, 3, "open"], [39.5, 3, "open"], [45.5, 3, "open"]])
	hwall(13, -14, 47, y, [[-8, 1.4, "door"], [0, 3, "open"], [33.5, 3, "open"], [39.5, 3, "open"], [45.5, 3, "open"]])
	hwall(20, -55, 47, y, [[-36.5, 3, "open"], [-8, 1.4, "door"], [0, 3, "open"], [9, 1.4, "door"], [24, 1.4, "door"], [33.5, 3, "open"], [39.5, 3, "open"], [45.5, 3, "open"]])
	hwall(23, -55, 55, y, [[-50, 6, "skip"], [-35.5, 1.4, "door"], [-24.5, 1.4, "door"], [-13.5, 1.4, "door"], [-2.5, 1.4, "door"], [8.5, 1.4, "door"], [19.5, 1.4, "door"], [30.5, 1.4, "door"], [41.5, 1.4, "door"], [51, 1.4, "door"]])
	hwall(37.5, -55, 55, y, [])
	hwall(30, -55, -41, y, [])
	hwall(14.5, 47, 55, y, [])   # split between the two east iso wards

	vwall(-55, -37.5, 37.5, y, [])
	vwall(55, -37.5, 37.5, y, [])
	# North patient rooms.
	for dx in [-44, -33, -22, -11, -1.5, 1.5, 11, 22, 33, 44]:
		vwall(dx, -37.5, -28, y, [])
	# Nurse-station band.
	for dx in [-38, -35, -15, -1.5, 1.5, 15, 32, 35, 44, 47]:
		vwall(dx, -25, -14, y, [])
	# Theatre/ICU band.
	vwall(-38, -11, 3, y, [[-4, 1.4, "door"]])
	vwall(-35, -11, 3, y, [])
	for dx in [-18, -1.5, 1.5, 7.5, 13.5, 24]:
		vwall(dx, -11, -4, y, [])
	for dx in [-20, -1.5, 1.5, 14, 24]:
		vwall(dx, -4, 3, y, [])
	for dx in [32, 35, 44, 47]:
		vwall(dx, -11, 3, y, [])
	# Physio band.
	for dx in [-38, -35, -14, -1.5, 1.5, 16, 32, 35]:
		vwall(dx, 6, 20, y, [])
	vwall(44, 6, 20, y, [])
	vwall(47, 6, 23, y, [[10, 1.4, "door"], [19, 1.4, "door"]])
	# South patient rooms.
	for dx in [-53, -47, -41]:
		vwall(dx, 23, 30, y, [])
	for dx in [-30, -19, -8, 3, 14, 25, 36, 47]:
		vwall(dx, 23, 37.5, y, [])

	# Nurse station desks.
	counter(-8.25, -19.5, 5, y)
	counter(8.25, -19.5, 5, y)


# ---------------------------------------------------------------- lights

func _lights() -> void:
	# Corridor CEILING FIXTURES on both floors: real visible tube lights.
	# Most are dead, a few burn dimly, a few flicker (random every build).
	# Floor 1 ceiling = underside of the mid slab (3.9), floor 2 = 8.1.
	for fy in [3.9, Y2 + 4.0]:
		# East-west corridors: fixtures run along X.
		for zc in [-26.5, -12.5, 4.5, 21.5]:
			for xc in [-44, -22, 0, 22, 44]:
				ceiling_light(xc, fy, zc, _light_state())
		# North-south corridors: fixtures turned 90 degrees.
		for p in [[-36.5, -6], [-36.5, 12], [0, -20], [0, 10], [33.5, -6], [33.5, 12], [45.5, -6], [45.5, 12]]:
			ceiling_light(p[0], fy, p[1], _light_state(), true)
	# Key rooms, floor 1.
	for p in [[-9, -32.5], [-47, -32.5], [21, -32.5], [47, -32.5], [35, -31.5], [-46, -19.5], [-8, -19.5], [39.5, -19.5], [-26.5, -7.5], [-46, -4], [39.5, -4], [7.5, -0.5], [-24.5, 13], [-32, 30], [0, 30], [16, 30], [47, 30]]:
		lamp(p[0], 3.3, p[1])
	# Key rooms, floor 2.
	for p in [[-8, -19.5], [8, -19.5], [-25, -19.5], [-26.5, -7.5], [-10, -7.5], [39.5, -4], [-24.5, 13], [-46, -4]]:
		lamp(p[0], Y2 + 3.3, p[1])


# ---------------------------------------------------------------- save

func _own(n: Node) -> void:
	for c in n.get_children():
		c.owner = root
		# Don't dig inside instanced scenes (player/entity) - they save themselves.
		if c.scene_file_path == "":
			_own(c)


func _save() -> void:
	_own(root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		print("BUILD FAILED: pack error ", err)
	else:
		err = ResourceSaver.save(packed, "res://main.tscn")
		if err != OK:
			print("BUILD FAILED: save error ", err)
		else:
			print("MAP BUILD DONE - main.tscn written")
	get_tree().quit()
