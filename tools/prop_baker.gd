# One-time tool: converts each prop glb into a saved Godot scene
# (assets/props/baked/*.scn). The map builder then places those scenes
# directly into main.tscn - no loading work at game launch any more.
# Re-run tools/prop_baker.tscn only if the glb files change.

extends Node3D

const FILES := {
	"table": "basic_table.glb",
	"chair": "chair_hospital.glb",
	"bed_a": "hospital_bed.glb",
	"bed_b": "hospital_bed (1).glb",
	"cupboard": "hospital_cupboard.glb",
	"trolley": "hospital_trolley.glb",
	"lab_trolley": "laboratory__hospital_troly.glb",
	"wall_cabinet": "medicine_wall_cupboard_hospital.glb",
	"radiator": "radiator_-_11mb.glb",
	"saline": "saline_stand_hospital_equipment._blender.glb",
}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/props/baked")
	for key in FILES:
		_bake(key, FILES[key])
	print("PROP BAKE DONE")
	get_tree().quit()


func _bake(key: String, file: String) -> void:
	var doc := GLTFDocument.new()
	var gltf := GLTFState.new()
	if doc.append_from_file("res://assets/props/" + file, gltf) != OK:
		print("FAILED TO READ: ", file)
		return
	var scene := doc.generate_scene(gltf)
	if scene == null:
		print("NO SCENE IN: ", file)
		return
	# Every node needs an owner or pack() won't include it in the save.
	_own_all(scene, scene)
	var packed := PackedScene.new()
	if packed.pack(scene) != OK:
		print("PACK FAILED: ", key)
	else:
		var err := ResourceSaver.save(packed, "res://assets/props/baked/" + key + ".scn")
		print(key, (" saved" if err == OK else " SAVE FAILED " + str(err)))
	scene.free()


func _own_all(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own_all(c, root)
