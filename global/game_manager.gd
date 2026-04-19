extends Node

var qna: Array = []
var index: int = 0
var loaded: bool = false

var player_answers: Array = []
var input_locked: bool = true

var api_url := "http://127.0.0.1:8000/qna"
var submit_url := "http://127.0.0.1:8000/submit"


# -------------------------
# INIT
# -------------------------

func _ready():
    signalBus.connect("answer_selected", _on_answer_selected)
    signalBus.connect("ui_ready_for_input", _on_ui_ready)

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

    start_game()


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


# Called by UI when typing animation is done
func _on_ui_ready():
    input_locked = false


func _on_answer_selected(choice: String):
    if input_locked:
        return

    if choice != "red" and choice != "blue":
        return

    answer(choice)


func answer(choice: String):
    if is_finished():
        return

    input_locked = true

    var q = qna[index]

    var response_text := ""
    if choice == "red":
        response_text = q.get("red_response", "")
    else:
        response_text = q.get("blue_response", "")

    player_answers.append({
        "question": q["question"],
        "choice": choice,
        "response": response_text
    })

    index += 1
    send_current_question()


func is_finished() -> bool:
    return index >= qna.size()


# -------------------------
# FINISH + SERVER SUBMIT
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

    if response_code == 200:
        var data = JSON.parse_string(body.get_string_from_utf8())
        if data != null and data.has("commentary"):
            commentary = data["commentary"]

    signalBus.emit_signal("game_finished", commentary)