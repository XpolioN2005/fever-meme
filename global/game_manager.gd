extends Node

# -------------------------
# STATE
# -------------------------
var qna: Array = []
var index: int = 0
var loaded: bool = false

var player_answers: Array = []

var input_locked: bool = true
var game_started := false
var game_finished := false
var evaluation_mode := false
var eval_playing := false

var _pending_commentary: Dictionary = {}

var question_audio_playing := false
var result_shown := false

# prevents double start spam
var start_locked := false


# -------------------------
# API
# -------------------------
var api_base := "https://fever-meme.onrender.com"
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
# NETWORK
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
# DATA
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
	loaded = true

	signalBus.emit_signal("data_loaded")


# =========================================================
# RESET (FULL CLEAN STATE)
# =========================================================
func reset_game():
	index = 0
	player_answers.clear()

	input_locked = true
	game_started = false
	game_finished = false
	evaluation_mode = false
	eval_playing = false

	_pending_commentary = {}
	question_audio_playing = false
	result_shown = false

	start_locked = false


# =========================================================
# START GAME (STRICT SINGLE ENTRY)
# =========================================================
func start_game():
	if start_locked:
		return

	if qna.is_empty():
		return

	if game_started:
		return

	start_locked = true

	reset_game()

	game_started = true
	input_locked = true

	index = 0
	_show_question()


# =========================================================
# GAME FLOW
# =========================================================
func _show_question():
	if game_finished:
		return

	if result_shown:
		return

	if index >= qna.size():
		finish_game()
		return

	input_locked = true
	question_audio_playing = true

	var q = qna[index]

	signalBus.emit_signal(
		"update_qna",
		q["question"],
		q["red_option"],
		q["blue_option"]
	)

	var audio = q.get("question_audio", "")
	if audio != "":
		_play_question_audio(audio)
	else:
		_on_question_audio_finished()


func _on_ui_ready():
	if game_started and not question_audio_playing and not result_shown:
		input_locked = false


# =========================================================
# QUESTION AUDIO
# =========================================================
func _play_question_audio(url: String):
	http_audio.request_completed.connect(_on_question_audio_done, CONNECT_ONE_SHOT)
	http_audio.request(api_base + url)


func _on_question_audio_done(_result, response_code, _headers, body):
	if response_code != 200:
		_on_question_audio_finished()
		return

	_play_stream(body, _on_question_audio_finished)


func _on_question_audio_finished():
	question_audio_playing = false
	input_locked = false


# =========================================================
# ANSWERS
# =========================================================
func _on_answer_selected(choice: String):
	if not game_started:
		return

	if input_locked or game_finished or result_shown:
		return

	if choice != "red" and choice != "blue":
		return

	_process_answer(choice)


func _process_answer(choice: String):
	input_locked = true

	var q = qna[index]

	var response = q.get(choice + "_response", "")
	var audio = q.get(choice + "_audio", "")

	player_answers.append({
		"question": q["question"],
		"choice": choice,
		"response": response
	})

	if audio != "":
		_play_game_audio(audio)
	else:
		_next()


func _next():
	index += 1
	_show_question()


# =========================================================
# FINISH GAME
# =========================================================
func finish_game():
	game_finished = true
	evaluation_mode = true

	signalBus.emit_signal("evaluation_loading")

	api_post(
		api_submit,
		{"answers": player_answers},
		_on_submit_done
	)


# =========================================================
# ANSWER AUDIO
# =========================================================
func _play_game_audio(url: String):
	_play_audio(url, _on_game_audio_done)


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
	var is_worthless := false

	if response_code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if data != null:
			commentary = data.get("commentary", "")
			audio = data.get("audio", "")
			is_worthless = data.get("is_worthless", false)

	_pending_commentary = {
		"commentary": commentary,
		"is_worthless": is_worthless
	}

	if audio != "":
		eval_playing = true
		_play_eval_audio(audio)
	else:
		_emit_and_finalize()


func _play_eval_audio(url: String):
	_play_audio(url, _on_eval_audio_done)


func _on_eval_audio_done(_result, response_code, _headers, body):
	if response_code != 200:
		_emit_and_finalize()
		return

	_play_stream(body, _on_eval_finished)


func _on_eval_finished():
	eval_playing = false
	_emit_and_finalize()


func _emit_and_finalize():
	signalBus.emit_signal("game_finished", _pending_commentary)
	_finalize_game()


func _finalize_game():
	evaluation_mode = false
	game_finished = true
	input_locked = true
	result_shown = true
	start_locked = false


# =========================================================
# AUDIO STREAM
# =========================================================
func _play_stream(body: PackedByteArray, on_finish: Callable):
	var stream = AudioStreamMP3.new()
	stream.data = body

	audio_player.stream = stream
	audio_player.play()

	audio_player.finished.connect(on_finish, CONNECT_ONE_SHOT)