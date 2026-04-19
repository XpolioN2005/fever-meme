extends StaticBody3D

enum ButtonType {
	RED,
	BLUE,
	START
}

@export var type: ButtonType = ButtonType.RED

@onready var mesh: MeshInstance3D = %btn
var material: StandardMaterial3D

# -------------------------
# STATE
# -------------------------
var data_loaded: bool = false


func _ready():
	add_to_group("btn")

	_setup_material()
	_update_visual()

	signalBus.connect("data_loaded", _on_data_loaded)


# -------------------------
# DATA LOADED
# -------------------------
func _on_data_loaded():
	data_loaded = true


# -------------------------
# MATERIAL
# -------------------------
func _setup_material():
	material = mesh.get_surface_override_material(0)

	if material == null:
		material = StandardMaterial3D.new()
		mesh.set_surface_override_material(0, material)


# -------------------------
# VISUAL
# -------------------------
func _update_visual():
	match type:
		ButtonType.RED:
			material.albedo_color = Color(1, 0, 0)

		ButtonType.BLUE:
			material.albedo_color = Color(0, 0, 1)

		ButtonType.START:
			material.albedo_color = Color(0, 1, 0)


# -------------------------
# INPUT
# -------------------------
func press():
	# BLOCK START UNTIL DATA IS READY
	if type == ButtonType.START and not data_loaded:
		return

	match type:
		ButtonType.RED:
			signalBus.emit_signal("answer_selected", "red")

		ButtonType.BLUE:
			signalBus.emit_signal("answer_selected", "blue")

		ButtonType.START:
			signalBus.emit_signal("game_start")