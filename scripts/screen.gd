extends Node3D

@onready var question_label: Label3D = $question
@onready var red_label: Label3D = $red
@onready var blue_label: Label3D = $blue
@onready var counter_label: Label3D = $counter

var typing: bool = false

func _ready() -> void:
	signalBus.connect("update_qna", _on_update_qna)
	signalBus.connect("evaluation_loading", _on_loading)
	signalBus.connect("game_finished", _on_game_finished)

	var title: String = "The Worthless Game"
	var red: String = "skip 💀"
	var blue: String = "i'm him"

	await show_sequence(title, red, blue)

func _on_game_finished(data: Dictionary) -> void:
	typing = true

	var is_worthless: bool = data.get("is_worthless", false)

	question_label.text = ""

	if is_worthless:
		await typewriter(question_label, "RESULT: WORTHLESS")
	else:
		await typewriter(question_label, "RESULT: NOT WORTHLESS")

	red_label.text = ""
	blue_label.text = ""
	counter_label.text = ""

	typing = false

func _on_loading() -> void:
	typing = true

	question_label.text = ""
	red_label.text = ""
	blue_label.text = ""
	counter_label.text = ""

	await typewriter(question_label, "AI is judging your worthlessness...")

	typing = false

func _on_update_qna(question: String, red: String, blue: String) -> void:
	print("screen recevied")
	if typing:
		print("still styping")
		return
	
	_update_counter()
	await show_sequence(question, red, blue)

func _update_counter() -> void:
	var current := GameManager.index + 1
	counter_label.text = str(current) + " / 10"

func show_sequence(question: String, red: String, blue: String) -> void:
	typing = true

	await fit_label(question_label, question, 7.0, 1.5, 80, 30)
	await fit_label(red_label, red, 3.0, 0.8, 50, 24)
	await fit_label(blue_label, blue, 3.0, 0.8, 50, 24)

	await typewriter(question_label, question)
	await get_tree().create_timer(0.3).timeout

	await typewriter(red_label, red)
	await get_tree().create_timer(0.2).timeout

	await typewriter(blue_label, blue)

	signalBus.emit_signal("ui_ready_for_input")
	typing = false


func typewriter(label: Label3D, text: String, speed: float = 0.03) -> void:
	label.text = ""
	for i in text.length():
		label.text += text[i]
		await get_tree().create_timer(speed).timeout


func fit_label(label: Label3D, text: String, max_width_world: float, max_height_world: float, max_font: int, min_font: int) -> void:
	label.visible = false
	label.text = text

	# STEP 1: Dynamic pixel size based on text length (simple heuristic)
	var length := text.length()

	# Tune this curve as needed
	if length < 20:
		label.pixel_size = 0.008
	elif length < 60:
		label.pixel_size = 0.006
	else:
		label.pixel_size = 0.004

	# STEP 2: Set wrapping width using FINAL pixel_size
	var max_width_px: float = max_width_world / label.pixel_size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.width = max_width_px

	# STEP 3: Fit using font size only
	label.font_size = max_font

	await get_tree().process_frame

	var current_font := max_font

	while current_font > min_font:
		var size: Vector3 = label.get_aabb().size

		if size.y <= max_height_world:
			break

		current_font -= 2
		label.font_size = current_font
		await get_tree().process_frame

	label.text = ""
	label.visible = true