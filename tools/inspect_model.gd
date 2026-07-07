# Throwaway tool: loads the hospital model, prints its overall size and parts,
# then quits. Lets the AI read real numbers so the interior can be built to fit.

extends Node3D


func _ready() -> void:
	# Load the hospital model file.
	var scene = load("res://assets/jejungwon_hospital.glb")
	if scene == null:
		print("MODEL FAILED TO LOAD")
		get_tree().quit()
		return

	# Drop it into the world so global positions are real.
	var inst = scene.instantiate()
	add_child(inst)

	# Walk every mesh and grow one big box around all of them.
	var total := AABB()
	var first := true
	var mesh_count := 0
	var stack: Array = [inst]
	while stack.size() > 0:
		var n = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			mesh_count += 1
			# get_aabb() is in the mesh's local space; move it to world space.
			var ab: AABB = n.global_transform * n.get_aabb()
			if first:
				total = ab
				first = false
			else:
				total = total.merge(ab)
		for c in n.get_children():
			stack.append(c)

	print("=== MODEL INFO ===")
	print("mesh instances: ", mesh_count)
	print("size (x,y,z): ", total.size)
	print("min corner: ", total.position)
	print("max corner: ", total.position + total.size)
	print("center: ", total.position + total.size * 0.5)

	# List the top-level parts so we can see how it's split up.
	print("--- top level children ---")
	for c in inst.get_children():
		print(c.name, "  (", c.get_class(), ")")

	print("=== DONE ===")
