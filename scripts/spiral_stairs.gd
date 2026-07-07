# Builds a round (spiral) staircase out of small ramp pieces.
#
# It makes a smooth helical ramp that winds up one full turn from the floor it
# sits on (y=0 locally) to the floor above (y=total_height). We use a smooth
# ramp instead of real steps so the player walks up it without snagging.
#
# This node is a StaticBody3D placed under the Nav region, so the navmesh bakes
# over it and the entity can follow the player up and down.

extends StaticBody3D

# Total height to climb (ground floor to second floor).
@export var total_height: float = 4.0
# Distance from the centre pole to the middle of the walking path.
@export var radius: float = 2.0
# How many full turns the spiral makes on the way up.
@export var turns: float = 1.0
# How many little ramp pieces make up the spiral (more = smoother).
@export var steps: int = 24
# Width of the walking path.
@export var path_width: float = 1.7
# Thickness of the ramp pieces.
@export var thickness: float = 0.3


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.52)
	mat.roughness = 0.9

	for i in steps:
		# Angle and height at the start and end of this piece.
		var a0: float = turns * TAU * float(i) / float(steps)
		var a1: float = turns * TAU * float(i + 1) / float(steps)
		var h0: float = total_height * float(i) / float(steps)
		var h1: float = total_height * float(i + 1) / float(steps)

		# The two ends of this piece, out on the circle.
		var p0 := Vector3(radius * cos(a0), h0, radius * sin(a0))
		var p1 := Vector3(radius * cos(a1), h1, radius * sin(a1))

		var center: Vector3 = (p0 + p1) * 0.5
		var len_dir: Vector3 = (p1 - p0).normalized()
		# A touch longer so neighbouring pieces overlap with no gaps.
		var length: float = p0.distance_to(p1) + 0.2

		# Build a box that lies along the path: X = length, Y = up, Z = width.
		var z_axis: Vector3 = len_dir.cross(Vector3.UP).normalized()
		var y_axis: Vector3 = z_axis.cross(len_dir).normalized()
		var seg_basis := Basis(len_dir, y_axis, z_axis)
		var xform := Transform3D(seg_basis, center)

		var seg_size := Vector3(length, thickness, path_width)

		# Visible ramp piece.
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = seg_size
		bm.material = mat
		mi.mesh = bm
		mi.transform = xform
		add_child(mi)

		# Matching collision so you can stand on it and the navmesh can bake it.
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = seg_size
		cs.shape = bs
		cs.transform = xform
		add_child(cs)

	# Central pole, just for looks.
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.3
	cyl.height = total_height
	cyl.material = mat
	pole.mesh = cyl
	pole.position = Vector3(0, total_height * 0.5, 0)
	add_child(pole)
