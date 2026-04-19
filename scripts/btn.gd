extends StaticBody3D

@export var is_red: bool = true

@onready var mesh: MeshInstance3D = %btn
var material: StandardMaterial3D


func _ready():
	add_to_group("btn")
	# duplicate material so each button is independent
	material = mesh.get_surface_override_material(0)

	if material == null:
		material = StandardMaterial3D.new()
		mesh.set_surface_override_material(0, material)

	update_color()


func update_color():
	if is_red:
		material.albedo_color = Color(1, 0, 0)  # red
	else:
		material.albedo_color = Color(0, 0, 1)  # blue


func set_mode_red():
	is_red = true
	update_color()


func set_mode_blue():
	is_red = false
	update_color()


# Call this from raycast or input
func press():
	if is_red:
		signalBus.emit_signal("answer_selected", "red")
	else:
		signalBus.emit_signal("answer_selected", "blue")