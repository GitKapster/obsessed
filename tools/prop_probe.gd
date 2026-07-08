# Throwaway tool: loads every prop glb in assets/props, prints its real size
# and which way it sits, then quits. Run tools/prop_probe.tscn once - the
# numbers tell us how much to scale each prop when placing it in the map.

extends Node3D

const PROPS := [
	"basic_table.glb",
	"chair_hospital.glb",
	"hospital_bed.glb",
	"hospital_bed (1).glb",
	"hospital_cupboard.glb",
	"hospital_stuff.glb",
	"hospital_trolley.glb",
	"laboratory__hospital_troly.glb",
	"medicine_wall_cupboard_hospital.glb",
	"radiator_-_11mb.glb",
	"saline_stand_hospital_equipment._blender.glb",
]


var report := ""


func _ready() -> void:
	for f in PROPS:
		_probe("res://assets/props/" + f)
	# Also save the numbers to a file, in case the console output gets cut off.
	var fa := FileAccess.open("res://tools/prop_probe_report.txt", FileAccess.WRITE)
	fa.store_string(report)
	fa.close()
	print("PROP PROBE DONE")
	get_tree().quit()


func _out(line: String) -> void:
	print(line)
	report += line + "\n"


func _probe(path: String) -> void:
	# Load the glb the same way the entity model is loaded (no import needed).
	var doc := GLTFDocument.new()
	var gltf := GLTFState.new()
	if doc.append_from_file(path, gltf) != OK:
		_out("FAILED TO READ: " + path)
		return
	var scene := doc.generate_scene(gltf)
	if scene == null:
		_out("NO SCENE IN: " + path)
		return
	add_child(scene)

	# One big box around all its meshes = the prop's real size.
	var total := AABB()
	var first := true
	var meshes := 0
	var stack: Array = [scene]
	while stack.size() > 0:
		var n = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			meshes += 1
			var ab: AABB = n.global_transform * n.mesh.get_aabb()
			if first:
				total = ab
				first = false
			else:
				total = total.merge(ab)
		for c in n.get_children():
			stack.append(c)

	_out("=== " + path.get_file())
	_out("  meshes: " + str(meshes))
	_out("  size: " + str(total.size))
	_out("  min: " + str(total.position) + "  max: " + str(total.position + total.size))
	# Top-level parts, in case one file holds several separate props.
	for c in scene.get_children():
		_out("  child: " + str(c.name))
	scene.queue_free()
