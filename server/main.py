from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import requests
import json
import os
import uuid
import edge_tts
import asyncio
import logging
from typing import List

import time
import random

MAX_RETRIES = 5
BASE_DELAY = 1.5  # seconds

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://xpolion.itch.io",
        "https://html.itch.zone"
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# -------------------------
# CONFIG
# -------------------------
API_KEY = os.getenv("GEMINI_API_KEY")
if not API_KEY:
    raise RuntimeError("GEMINI_API_KEY is not set")

URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/"
    "gemini-2.5-flash-lite:generateContent?key=" + API_KEY
)

AUDIO_DIR = "audio"
os.makedirs(AUDIO_DIR, exist_ok=True)

POOL_FILE = "pool.json"
STATE_FILE = "state.json"

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("system")

sem = asyncio.Semaphore(5)

# -------------------------
# POOL SYSTEM
# -------------------------
POOL_SIZE = 5
pool: List[dict] = []
pool_lock = asyncio.Lock()
counter = 0
refill_running = False


# -------------------------
# PERSISTENCE (ADDED ONLY)
# -------------------------
def load_pool_file():
    global pool
    if os.path.exists(POOL_FILE):
        with open(POOL_FILE, "r") as f:
            pool[:] = json.load(f)
    else:
        pool[:] = []


def save_pool_file():
    with open(POOL_FILE, "w") as f:
        json.dump(pool, f)


def load_state_file():
    global counter
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, "r") as f:
            counter = json.load(f).get("counter", 0)


def save_state_file():
    with open(STATE_FILE, "w") as f:
        json.dump({"counter": counter}, f)


def ensure_loaded():
    if not hasattr(app.state, "loaded"):
        load_pool_file()
        load_state_file()
        app.state.loaded = True


# -------------------------
# GEMINI CALL
# -------------------------
def call_gemini(prompt: str) -> str:
    payload = {
        "contents": [{"parts": [{"text": prompt}]}]
    }

    for attempt in range(MAX_RETRIES):
        try:
            start = time.time()

            res = requests.post(URL, json=payload, timeout=30)

            duration = time.time() - start
            logger.info(
                f"Gemini call attempt={attempt+1} status={res.status_code} time={duration:.2f}s")

            if res.status_code == 200:
                return res.json()["candidates"][0]["content"]["parts"][0]["text"]

            # rate limit or transient failure
            logger.warning(f"Gemini error: {res.status_code} {res.text}")

        except Exception as e:
            logger.error(f"Gemini exception attempt={attempt+1}: {e}")

        # exponential backoff + jitter
        sleep_time = BASE_DELAY * (2 ** attempt) + random.uniform(0, 0.5)
        logger.info(f"Retrying in {sleep_time:.2f}s")
        time.sleep(sleep_time)

    raise RuntimeError("Gemini failed after retries")


# -------------------------
# CLEAN JSON
# -------------------------
def clean_json(text: str):
    text = text.strip()

    if text.startswith("```"):
        text = text.split("```")[1]
        text = text.replace("json", "", 1).strip()

    if text.endswith("```"):
        text = text[:-3].strip()

    return json.loads(text)


# -------------------------
# TTS
# -------------------------
async def generate_voice(text: str) -> str:
    async with sem:
        try:
            file_id = uuid.uuid4()
            filename = f"{file_id}.mp3"
            path = os.path.join(AUDIO_DIR, filename)

            communicate = edge_tts.Communicate(
                text=text,
                voice="en-US-BrianMultilingualNeural",
            )

            await communicate.save(path)

            return "/audio/" + filename

        except Exception as e:
            logger.error(f"TTS ERROR: {e}")
            return ""


# -------------------------
# QNA PROMPT (UNCHANGED)
# -------------------------
QNA_PROMPT = """
Create a FUNNY AI commentary game dataset.

Return ONLY valid JSON. No markdown. No code blocks. No extra text.

Generate exactly 10 items.

Game concept:
This is a "Worthless Judgment System".
A SYSTEM acts as a cold judge that evaluates the player's decisions and assigns "worthlessness energy" implicitly through responses.

IMPORTANT:
- The narrator must NEVER refer to itself as "AI"
- It must always refer to itself as "the system" or "the judge"

Structure requirement:
- 7 items must be absurd / meme-like decisions
- 3 items must be disguised real-life judgment questions
  (they look funny or simple, but actually test real behavior, discipline, habits, or decision-making)

For the 3 disguised ones:
- question must look casual or humorous
- but choices must reflect real behavioral tradeoffs
- example types: procrastination, discipline, social behavior, focus, impulse control

Each item must include:
- question
- red_option
- blue_option
- red_response
- blue_response

STRICT RULE:
- red_option and blue_option MUST be very short
- MAX 5 to 6 words each option
- no long sentences in options
- options must be punchy and simple

Rules:
- responses MUST sound like a system judge voice
- tone: cold, humorous, slightly judgmental, dramatic system evaluation
- max 2 sentences per response
- no emojis
- no markdown
- no explanations outside JSON

Style:
- The judge evaluates human behavior like a ranking system for uselessness
- responses imply judgment but never explicitly show score
- tone becomes slightly more harsh as game progresses (optional variation)

Format:
{
  "qna": [
    {
      "question": "",
      "red_option": "",
      "blue_option": "",
      "red_response": "",
      "blue_response": ""
    }
  ]
}
"""


# -------------------------
# COMMENTARY PROMPT (UNCHANGED)
# -------------------------
def build_eval_prompt(data: dict) -> str:
    return f"""
You are the Judge of the "Worthless Judgment System" final evaluation module.

The player has completed a 10-question decision simulation.
Among these, 3 questions are REAL BEHAVIOR CHECKS disguised as jokes, testing discipline, focus, and decision-making.
The remaining questions are absurd or meme-based.

IMPORTANT RULE:
Do NOT default to calling the player worthless.
You must evaluate based on actual behavioral patterns across all answers.
Some players may be NOT worthless if they show consistent good judgment in the disguised real questions.

If the player is NOT worthless:
- The system must still sound strict
- It must "push" the player harder
- It should imply potential and challenge them, not praise them
- Tone becomes sharp, like: "you barely passed system thresholds"

If the player IS worthless:
- commentary should be more mocking and final
- still humorous, but decisive

Return ONLY valid JSON.

No markdown. No extra text.

Input:
{json.dumps(data, indent=2)}

You must determine:
- whether the player is worthless (true/false)
- a short system commentary based on pattern evaluation

Output format:{{
            "is_worthless": true or false,
            "commentary": "1 to 3 sentences max. Cold system verdict based on behavioral consistency."
        }}

Rules:
- tone: system final judgment module
- must feel like classification + behavioral analysis system
- no emojis
- no lists
- no extra fields
- keep it concise but impactful
"""


# -------------------------
# GENERATE QNA
# -------------------------
async def generate_qna():
    raw = call_gemini(QNA_PROMPT)
    data = clean_json(raw)

    tasks = []
    for item in data["qna"]:
        tasks.append(generate_voice(item["question"]))
        tasks.append(generate_voice(item["red_response"]))
        tasks.append(generate_voice(item["blue_response"]))

    results = await asyncio.gather(*tasks)

    i = 0
    for item in data["qna"]:
        item["question_audio"] = results[i]
        item["red_audio"] = results[i + 1]
        item["blue_audio"] = results[i + 2]
        i += 3

    return data


# -------------------------
# REFILL POOL
# -------------------------
async def refill_pool():
    global refill_running

    async with pool_lock:
        if refill_running:
            return
        refill_running = True

    try:
        while True:
            async with pool_lock:
                if len(pool) >= POOL_SIZE:
                    break

            data = await generate_qna()

            async with pool_lock:
                pool.append(data)
                save_pool_file()

    finally:
        async with pool_lock:
            refill_running = False


def check_and_refill():
    if len(pool) <= 1:
        asyncio.create_task(refill_pool())


# -------------------------
# GET QNA
# -------------------------
@app.get("/qna")
async def get_qna():
    global counter

    ensure_loaded()

    async with pool_lock:

        if not pool:
            pool.append(await generate_qna())
            save_pool_file()

        data = pool.pop(0)
        counter += 1

        save_pool_file()
        save_state_file()

    check_and_refill()

    return {
        "id": counter,
        "data": data
    }


# -------------------------
# SUBMIT
# -------------------------
async def generate_commentary(payload: dict):
    prompt = build_eval_prompt(payload)

    raw = call_gemini(prompt)
    data = clean_json(raw)

    commentary = data.get("commentary", "No commentary")
    is_worthless = data.get("is_worthless", False)

    audio = await generate_voice(commentary)

    return commentary, is_worthless, audio


@app.post("/submit")
async def submit(payload: dict):
    commentary, is_worthless, audio = await generate_commentary(payload)

    return {
        "commentary": commentary,
        "is_worthless": is_worthless,
        "audio": audio
    }


# -------------------------
# POOL STATUS
# -------------------------
@app.get("/pool/status")
async def pool_status():
    return {
        "pool_size": len(pool),
        "counter": counter
    }


# -------------------------
# CLEAR POOL
# -------------------------
@app.post("/pool/clear")
async def clear_pool():
    global pool
    async with pool_lock:
        pool.clear()
        save_pool_file()
    return {"status": "pool cleared"}


# -------------------------
# CLEAR AUDIO
# -------------------------
@app.post("/audio/clear")
async def clear_audio():
    try:
        for f in os.listdir(AUDIO_DIR):
            os.remove(os.path.join(AUDIO_DIR, f))
        return {"status": "audio cleared"}
    except Exception as e:
        return {"error": str(e)}


@app.post("/pool/refill")
async def manual_refill_pool():
    global refill_running

    async with pool_lock:
        # prevent duplicate refill triggers
        if refill_running:
            return {"status": "already_refilling"}

        refill_running = True

    try:
        while True:
            async with pool_lock:
                if len(pool) >= POOL_SIZE:
                    break

            data = await generate_qna()

            async with pool_lock:
                pool.append(data)
                save_pool_file()

        return {
            "status": "pool_refilled",
            "pool_size": len(pool)
        }

    finally:
        async with pool_lock:
            refill_running = False
            save_pool_file()

# -------------------------
# STATIC AUDIO
# -------------------------
app.mount("/audio", StaticFiles(directory="audio"), name="audio")
