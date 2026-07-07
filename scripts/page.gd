# One collectible page pinned to a wall.
#
# The player looks at it and presses E - player.gd sees this body has a
# collect() method and calls it. We tell the manager, then remove ourselves.

extends StaticBody3D

signal collected

var taken := false  # guard so one page can't be grabbed twice


func collect() -> void:
	if taken:
		return
	taken = true
	collected.emit()
	queue_free()
