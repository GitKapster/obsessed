# Builds a simple straight staircase at runtime.
# It's actually a smooth tilted slab (a ramp), not real steps.
# The player walks up it because it's a gentle slope - the player
# controller can't auto-climb real steps, so a ramp stays snag-free.
# This matches how the spiral staircase works.
extends StaticBody3D

@export var total_height: float = 4.0   # how high it rises (metres) - one floor
@export var run: float = 8.0            # how far it travels along +Z (metres)
@export var width: float = 2.4          # how wide the steps are
@export var thickness: float = 0.4      # how thick the slab is

func _ready() -> void:
	# slope angle, and the length of the tilted slab (the hypotenuse)
	var angle := atan2(total_height, run)
	var slope_len := sqrt(run * run + total_height * total_height)

	# grey material so it blends with the rest of the greybox
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.36, 0.38)
	mat.roughness = 0.9

	# the visible ramp
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, thickness, slope_len)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	# tilt it so the +Z end points up, and lift it to the middle of the rise
	mi.rotation = Vector3(-angle, 0.0, 0.0)
	mi.position = Vector3(0.0, total_height * 0.5, run * 0.5)
	add_child(mi)

	# the matching collision so the player can stand on it
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, thickness, slope_len)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.rotation = mi.rotation
	col.position = mi.position
	add_child(col)
