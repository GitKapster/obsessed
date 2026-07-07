# A dying fluorescent ceiling light. It's lit most of the time but keeps
# cutting out in short, sputtery blinks - and hums quietly while it lives.
# build_map.gd puts this script on some of the corridor ceiling fixtures.
#
# The fixture (built by the map builder) has these children:
#   Tube  - the glowing tube mesh (we blink its glow)
#   Light - the OmniLight3D (we blink the actual light)

extends Node3D

@onready var light: OmniLight3D = $Light
@onready var tube: MeshInstance3D = $Tube

var tube_mat: StandardMaterial3D
var timer: float = 0.0
var lit: bool = true


func _ready() -> void:
	# The tube mesh + material are SHARED between every fixture in the
	# building (the builder caches them). Make our own copies, so blinking
	# THIS tube doesn't blink every tube on the map.
	var mesh_copy: BoxMesh = tube.mesh.duplicate()
	tube_mat = mesh_copy.material.duplicate()
	mesh_copy.material = tube_mat
	tube.mesh = mesh_copy

	# A faint electrical buzz coming from the fixture itself.
	var buzz := AudioStreamPlayer3D.new()
	buzz.stream = load("res://audio/buzz_loop.res")  # loops by itself
	buzz.volume_db = -18.0
	buzz.max_distance = 12.0
	buzz.unit_size = 3.0
	add_child(buzz)
	buzz.play()

	# Start each flickering light at a random point in its cycle, so they
	# don't all blink in step with each other.
	timer = randf_range(0.0, 2.0)


func _process(delta: float) -> void:
	timer -= delta
	if timer <= 0.0:
		lit = not lit
		# Lit for a good stretch, dark only in short blinks.
		timer = randf_range(0.15, 2.5) if lit else randf_range(0.05, 0.4)
		light.visible = lit
		tube_mat.emission_energy_multiplier = 1.6 if lit else 0.0
