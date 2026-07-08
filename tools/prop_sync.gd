# Throwaway tool: reads every prop's CURRENT position/rotation out of
# main.tscn (including ones moved by hand in the editor) and writes them as
# ready-to-paste PROP_PLACES lines. Lets hand-tweaks in the editor survive a
# map rebuild: run this, paste the list into build_map.gd, then rebuild.

extends Node3D


func _ready() -> void:
	var packed: PackedScene = load("res://main.tscn")
	if packed == null:
		print("SYNC FAILED: can't load main.tscn")
		get_tree().quit()
		return
	# NOT added to the tree, so none of the game scripts start running.
	var main := packed.instantiate()
	var nav := main.get_node_or_null("Nav")
	if nav == null:
		print("SYNC FAILED: no Nav node")
		main.free()
		get_tree().quit()
		return

	var lines := ""
	var count := 0
	for c in nav.get_children():
		if not str(c.name).begins_with("Prop"):
			continue
		# Which prop is it? The Model child remembers its baked scene file.
		var model = c.get_node_or_null("Model")
		if model == null or model.scene_file_path == "":
			print("SKIPPED (no model): ", c.name)
			continue
		var key: String = model.scene_file_path.get_file().get_basename()
		var p: Vector3 = c.position
		var yaw := roundf(rad_to_deg(c.rotation.y) * 10.0) / 10.0
		lines += '\t["%s", Vector3(%s, %s, %s), %s],\n' % [
			key, _num(p.x), _num(p.y), _num(p.z), str(yaw)]
		count += 1

	var fa := FileAccess.open("res://tools/prop_sync_report.txt", FileAccess.WRITE)
	fa.store_string(lines)
	fa.close()
	main.free()
	print("PROP SYNC DONE - ", count, " props written to tools/prop_sync_report.txt")
	get_tree().quit()


# Tidy number: up to 3 decimals, no trailing zeros.
func _num(v: float) -> String:
	var s := "%.3f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s
