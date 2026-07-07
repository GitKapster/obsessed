# One camcorder battery lying around the hospital. The player grabs it with E
# (the same interact ray that collects pages calls collect() on us).
# Grabbing it fully recharges the camcorder. page_manager.gd spawns these.

extends StaticBody3D

signal collected

var taken := false


func collect() -> void:
	if taken:
		return  # already grabbed (double-tap safety)
	taken = true
	collected.emit()
	queue_free()
