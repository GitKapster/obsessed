# Bakes the navigation mesh for the room when the game starts.
# The NavigationRegion3D wraps all the solid level geometry (floor, walls,
# crates, pillars). Baking works out where the entity can walk, leaving holes
# around obstacles so it paths AROUND them instead of through them.

extends NavigationRegion3D


func _ready() -> void:
	# Only bake INSIDE the building. Without this box, the navmesh also
	# bakes on TOP of the roof and on the sliver of ground outside the
	# walls - and the entity could teleport up/out there. The box stops
	# just below the roof (y 6.5) and just inside the outer walls.
	navigation_mesh.filter_baking_aabb = AABB(
		Vector3(-54.8, -0.5, -37.3), Vector3(109.6, 7.0, 74.6))
	# Bake right away (false = do it now, not on a background thread).
	bake_navigation_mesh(false)
