extends Node

# -------------------------
# STATE
# -------------------------
var qna: Array = []
var index: int = 0
var loaded: bool = false

var player_answers: Array = []

var input_locked: bool = true
var game_finished := false
var evaluation_mode := false

# -------------------------
# API
# -------------------------
var api_base := "http://127.0.0.1:8000"
var api_qna := api_base + "/qna"
var api_submit := api_base + "/submit"

# -------------------------
# NODES
# -------------------------
var audio_player: AudioStreamPlayer
var http_audio: HTTPRequest
var http_data: HTTPRequest

# =========================================================
# INIT
# =========================================================
func _ready():
	_bind_signals()
	_init_nodes()
	load_dataset()


func _bind_signals():
	signalBus.connect("answer_selected", _on_answer_selected)
	signalBus.connect("ui_ready_for_input", _on_ui_ready)


func _init_nodes():
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)

	http_audio = HTTPRequest.new()
	add_child(http_audio)

	http_data = HTTPRequest.new()
	add_child(http_data)


# =========================================================
# NETWORK LAYER (GENERIC)
# =========================================================
func api_get(url: String, callback: Callable):
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(callback)
	http.request(url)


func api_post(url: String, payload: Dictionary, callback: Callable):
	var http = HTTPRequest.new()
	add_child(http)

	http.request_completed.connect(callback)

	http.request(
		url,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)


# =========================================================
# DATA LOADING
# =========================================================
func load_dataset():
	api_get(api_qna, _on_dataset_loaded)


func _on_dataset_loaded(_result, response_code, _headers, body):
	if response_code != 200:
		push_error("Dataset load failed")
		return

	var data = JSON.parse_string(body.get_string_from_utf8())

	if data == null or not data.has("qna"):
		push_error("Invalid dataset")
		return

	qna = data["qna"]
	index = 0
	loaded = true
	player_answers.clear()

	signalBus.emit_signal("data_loaded")
	start_game()


# =========================================================
# GAME FLOW
# =========================================================
func start_game():
	if qna.is_empty():
		return
	index = 0
	_show_question()


func _show_question():
	if game_finished:
		return

	if index >= qna.size():
		finish_game()
		return

	input_locked = true

	var q = qna[index]

	signalBus.emit_signal(
		"update_qna",
		q["question"],
		q["red_option"],
		q["blue_option"]
	)


func _on_ui_ready():
	input_locked = false


func _on_answer_selected(choice: String):
	if input_locked or game_finished:
		return
	if choice != "red" and choice != "blue":
		return

	_process_answer(choice)


# =========================================================
# ANSWER HANDLER
# =========================================================
func _process_answer(choice: String):
	input_locked = true

	var q = qna[index]

	var response = _get_response(q, choice)
	var audio = _get_audio(q, choice)

	player_answers.append({
		"question": q["question"],
		"choice": choice,
		"response": response
	})

	if audio != "":
		_play_game_audio(audio)
	else:
		_next()


func _get_response(q: Dictionary, choice: String) -> String:
	return q.get(choice + "_response", "")


func _get_audio(q: Dictionary, choice: String) -> String:
	return q.get(choice + "_audio", "")


# =========================================================
# GAME PROGRESSION
# =========================================================
func _next():
	index += 1
	_show_question()


func finish_game():
	game_finished = true

	api_post(
		api_submit,
		{"answers": player_answers},
		_on_submit_done
	)


# =========================================================
# AUDIO SYSTEM (SHARED)
# =========================================================
func _play_game_audio(url: String):
	_play_audio(url, _on_game_audio_done)


func _play_eval_audio(url: String):
	_play_audio(url, _on_eval_audio_done)


func _play_audio(url: String, callback: Callable):
	http_audio.request_completed.connect(callback, CONNECT_ONE_SHOT)
	http_audio.request(api_base + url)


func _on_game_audio_done(_result, response_code, _headers, body):
	if response_code != 200:
		_next()
		return

	_play_stream(body, _on_audio_finished)


func _on_audio_finished():
	_next()


# =========================================================
# EVALUATION
# =========================================================
func _on_submit_done(_result, response_code, _headers, body):
	var commentary := "Server error"
	var audio := ""

	if response_code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if data != null:
			commentary = data.get("commentary", "")
			audio = data.get("audio", "")

	game_finished = true
	evaluation_mode = true

	signalBus.emit_signal("game_finished", commentary)

	if audio != "":
		_play_eval_audio(audio)


func _on_eval_audio_done(_result, response_code, _headers, body):
	if response_code != 200:
		return

	_play_stream(body, _on_eval_finished)


func _on_eval_finished():
	evaluation_mode = false


# =========================================================
# AUDIO STREAM HELPER
# =========================================================
func _play_stream(body: PackedByteArray, on_finish: Callable):
	var stream = AudioStreamMP3.new()
	stream.data = body

	audio_player.stream = stream
	audio_player.play()

	audio_player.finished.connect(on_finish, CONNECT_ONE_SHOT)