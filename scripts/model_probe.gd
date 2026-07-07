# MODEL PROBE - one-shot tool. Copies the uploaded monster .glb into the
# project, loads it WITHOUT the editor import step (GLTFDocument reads the
# file at runtime), and prints everything we need to know to wire it up:
# the node tree, skeleton bones, animation names/lengths and its real size.
# Run tools/model_probe.tscn once and read the output.

extends Node

const SRC_PATH := "A:/Roaming/Claude/local-agent-mode-sessions/b1956a24-a285-42e8-920b-28a28dd921fd/3956e839-e539-4f62-8a6d-c2359d1f158d/local_92548db2-cc7f-4fb7-b62e-0b898e627ff6/uploads/smily_horror_monster.glb"
const DST_PATH := "res://assets/smily_horror_monster.glb"


func _ready() -> void:
	print("MODEL PROBE starting...")
	_copy_file()
	_probe()
	print("MODEL PROBE DONE")
	await get_tree().create_timer(30.0).timeout
	get_tree().quit()


# Copy the uploaded file into the project's assets folder (byte for byte).
func _copy_file() -> void:
	var src := FileAccess.open(SRC_PATH, FileAccess.READ)
	if src == null:
		push_error("could not open the uploaded file: " + SRC_PATH)
		return
	var bytes := src.get_buffer(src.get_length())
	src.close()
	var dst := FileAccess.open(DST_PATH, FileAccess.WRITE)
	dst.store_buffer(bytes)
	dst.close()
	print("copied %d KB to %s" % [bytes.size() / 1024, DST_PATH])


# Load the glb at runtime and report what's inside.
func _probe() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(DST_PATH, state)
	if err != OK:
		push_error("GLTF load failed (error %d)" % err)
		return
	var scene := doc.generate_scene(state)
	if scene == null:
		push_error("GLTF generate_scene returned null")
		return
	add_child(scene)
	_dump(scene, 0)

	# Total size: merge every visible mesh's bounding box.
	var aabb := AABB()
	var first := true
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	if not first:
		print("TOTAL SIZE: %.2f wide x %.2f tall x %.2f deep (metres)" %
				[aabb.size.x, aabb.size.y, aabb.size.z])
		print("FEET AT y=%.2f, HEAD AT y=%.2f" % [aabb.position.y, aabb.end.y])


# Print the node tree. For the interesting node types, add details.
func _dump(n: Node, depth: int) -> void:
	var line := "  ".repeat(depth) + n.name + " (" + n.get_class() + ")"
	if n is AnimationPlayer:
		line += "  ANIMATIONS:"
		print(line)
		for anim_name in (n as AnimationPlayer).get_animation_list():
			var a: Animation = (n as AnimationPlayer).get_animation(anim_name)
			print("  ".repeat(depth + 1) + "- \"%s\"  %.2f s, loop=%d" %
					[anim_name, a.length, a.loop_mode])
	elif n is Skeleton3D:
		var sk := n as Skeleton3D
		line += "  (%d bones)" % sk.get_bone_count()
		print(line)
		# Print every bone with its parent, so we can map hips/spine/head/legs.
		for i in sk.get_bone_count():
			var parent_id := sk.get_bone_parent(i)
			var parent_name: String = sk.get_bone_name(parent_id) if parent_id >= 0 else "-"
			print("  ".repeat(depth + 1) + "bone %d: %s  (parent: %s)" %
					[i, sk.get_bone_name(i), parent_name])
	elif n is MeshInstance3D:
		var mi := n as MeshInstance3D
		line += "  mesh=%s, %d surfaces" % [mi.mesh.get_class() if mi.mesh else "none",
				mi.mesh.get_surface_count() if mi.mesh else 0]
		print(line)
	else:
		print(line)
	for c in n.get_children():
		_dump(c, depth + 1)
