# CCTV still-shot tool (run tools/cctv_shots.tscn once, like the builder).
#
# It loads the level, flies a camera to a few "security camera" spots
# (high in a corner, tilted down), takes a picture of each, and saves
# them as PNGs in assets/. The main menu uses them as its background.
# Prints "CCTV SHOTS DONE" and quits when finished.
#
# To change the views: edit the SHOTS list and run this scene again.

extends Node3D

# [file name, camera position, point the camera looks at]
const SHOTS := [
	["cctv_lobby",    Vector3(-19.5, 3.5, -36.2), Vector3(-9.0, 0.6, -29.0)],
	["cctv_corridor", Vector3(-34.2, 3.5, -12.5), Vector3(0.0, 0.8, -12.5)],
	["cctv_yard",     Vector3(14.8, 3.5, -3.4),   Vector3(21.0, 0.2, 1.5)],
]


func _ready() -> void:
	# Bring in the level geometry.
	var level: Node = load("res://main.tscn").instantiate()
	add_child(level)

	# Kick out the things that would get in the way of a clean photo:
	# the player (its HUD draws on screen), the entity, and the pages.
	for n in ["Player", "Entity", "PageManager"]:
		var node := level.get_node_or_null(n)
		if node:
			node.free()

	# Our security camera. It only sees layer 1 (the level itself).
	var cam := Camera3D.new()
	cam.cull_mask = 1
	cam.fov = 68.0  # wide-ish lens, like a real CCTV camera
	add_child(cam)
	cam.make_current()

	# CCTV cameras have their own infrared light - and it saves the shots
	# from being pitch black inside the dark building.
	var light := OmniLight3D.new()
	light.omni_range = 32.0
	light.light_energy = 1.4
	light.shadow_enabled = true
	cam.add_child(light)

	# Let the level settle (shaders compile, navmesh bakes) before shooting.
	for i in 8:
		await RenderingServer.frame_post_draw

	for shot in SHOTS:
		cam.look_at_from_position(shot[1], shot[2])
		# Wait two drawn frames so the new view is actually on screen.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		# Shrink it - CCTV is low-res, and the shader adds the grain anyway.
		img.resize(640, 360, Image.INTERPOLATE_BILINEAR)
		img.save_png("res://assets/%s.png" % shot[0])
		print("CCTV SHOT SAVED: %s" % shot[0])

	print("CCTV SHOTS DONE")
	get_tree().quit()
