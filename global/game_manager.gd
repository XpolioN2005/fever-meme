extends Node

var qna: Array = []
var index: int = 0
var loaded: bool = false

var player_answers: Array = []
var input_locked: bool = true

var api_url := "http://127.0.0.1:8000/qna"
var submit_url := "http://127.0.0.1:8000/submit"

var audio_player: AudioStreamPlayer
var http_audio: HTTPRequest


# -------------------------
# INIT
# -------------------------

func _ready():
    signalBus.connect("answer_selected", _on_answer_selected)
    signalBus.connect("ui_ready_for_input", _on_ui_ready)

    audio_player = AudioStreamPlayer.new()
    add_child(audio_player)

    http_audio = HTTPRequest.new()
    add_child(http_audio)

    load_dataset()


# -------------------------
# DATA LOADING
# -------------------------

func load_dataset():
    var http = HTTPRequest.new()
    add_child(http)

    http.request_completed.connect(_on_dataset_loaded)
    http.request(api_url)


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


# -------------------------
# GAME FLOW
# -------------------------

func start_game():
    if qna.is_empty():
        return

    index = 0
    send_current_question()


func send_current_question():
    if is_finished():
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
    if input_locked:
        return

    if choice != "red" and choice != "blue":
        return

    answer(choice)


# -------------------------
# ANSWER + AUDIO PLAYBACK
# -------------------------

func answer(choice: String):
    if is_finished():
        return

    input_locked = true

    var q = qna[index]

    var response_text := ""
    var audio_url := ""

    if choice == "red":
        response_text = q.get("red_response", "")
        audio_url = q.get("red_audio", "")
    else:
        response_text = q.get("blue_response", "")
        audio_url = q.get("blue_audio", "")

    player_answers.append({
        "question": q["question"],
        "choice": choice,
        "response": response_text
    })

    if audio_url != "":
        play_audio(audio_url)
    else:
        advance_game()


func play_audio(url: String):
    http_audio.request_completed.connect(_on_audio_received, CONNECT_ONE_SHOT)
    http_audio.request("http://127.0.0.1:8000" + url)


func _on_audio_received(_result, response_code, _headers, body):
    if response_code != 200:
        advance_game()
        return

    var stream = AudioStreamMP3.new()
    stream.data = body

    audio_player.stream = stream
    audio_player.play()

    audio_player.finished.connect(advance_game, CONNECT_ONE_SHOT)


func advance_game():
    index += 1
    send_current_question()


func is_finished() -> bool:
    return index >= qna.size()


# -------------------------
# FINISH + EVALUATION
# -------------------------

func finish_game():
    var payload = {
        "answers": player_answers
    }

    var http = HTTPRequest.new()
    add_child(http)

    http.request_completed.connect(_on_submit_done)

    var json_body = JSON.stringify(payload)

    http.request(
        submit_url,
        ["Content-Type: application/json"],
        HTTPClient.METHOD_POST,
        json_body
    )


func _on_submit_done(_result, response_code, _headers, body):
    var commentary := "Server didn’t respond."
    var audio_url := ""

    if response_code == 200:
        var data = JSON.parse_string(body.get_string_from_utf8())
        if data != null:
            commentary = data.get("commentary", "")
            audio_url = data.get("audio", "")

    signalBus.emit_signal("game_finished", commentary)

    if audio_url != "":
        play_audio(audio_url)