# Tiny helper that runs the audio baker and keeps the window open a few
# seconds so any error messages can actually be read, then quits.

extends Node

func _ready() -> void:
	var baker_script = load("res://scripts/audio_baker.gd")
	if baker_script == null:
		print("BAKER SCRIPT FAILED TO LOAD - check for script errors above")
	else:
		var baker := Node.new()
		baker.set_script(baker_script)
		add_child(baker)  # adding it runs its _ready, which bakes everything
	await get_tree().create_timer(10.0).timeout
	get_tree().quit()
