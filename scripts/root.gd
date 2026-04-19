extends Node3D

@onready var anim: AnimationPlayer = $AnimationPlayer


func _ready():
	signalBus.connect("game_start", _on_game_start)
	signalBus.connect("game_finished", _on_game_finished)

	anim.animation_finished.connect(_on_animation_finished)


# -------------------------
# GAME START
# -------------------------
func _on_game_start():
	if anim.has_animation("start"):
		anim.play("start")


# -------------------------
# GAME END
# -------------------------
func _on_game_finished(_commentary):
	if anim.has_animation("start"):
		anim.play_backwards("start")


# -------------------------
# CALLED WHEN ANY ANIMATION FINISHES
# -------------------------
func _on_animation_finished(anim_name: StringName):
	if anim_name == "start":
		GameManager.start_game()