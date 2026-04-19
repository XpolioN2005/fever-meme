from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
import requests
import json
import os
import uuid
import edge_tts
import asyncio
import logging

app = FastAPI()

API_KEY = ""

URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/"
    "gemini-2.5-flash-lite:generateContent?key=" + API_KEY
)

AUDIO_DIR = "audio"
os.makedirs(AUDIO_DIR, exist_ok=True)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("tts")

sem = asyncio.Semaphore(5)

DATA = None

# -------------------------
# UTIL: GEMINI CALL (REUSED)
# -------------------------


def call_gemini(prompt: str) -> str:
    payload = {
        "contents": [{"parts": [{"text": prompt}]}]
    }

    res = requests.post(URL, json=payload)

    logger.info(f"GEMINI STATUS: {res.status_code}")

    return res.json()["candidates"][0]["content"]["parts"][0]["text"]


# -------------------------
# UTIL: CLEAN JSON (REUSED)
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
# UTIL: TTS (REUSED)
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

            logger.info(f"TTS DONE | {filename}")

            return "/audio/" + filename

        except Exception as e:
            logger.error(f"TTS FAILED: {e}")
            return ""


# -------------------------
# QNA PROMPT
# -------------------------
QNA_PROMPT = """
Create a FUNNY AI commentary game dataset.

Return ONLY valid JSON. No markdown. No code blocks.

Generate exactly 5 items.

Each item must have:
- question
- red_option
- blue_option
- red_response
- blue_response

Rules:
- responses MUST sound like spoken narration (TTS friendly)
- short sentences only (max 2 sentences)
- no emojis
- AI system commentary style

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
# COMMENTARY PROMPT BUILDER
# -------------------------
def build_eval_prompt(data: dict) -> str:
    return f"""
You are an AI game judge.

Analyze the player's answers and generate a funny, slightly dramatic commentary.

Return ONLY valid JSON.

Input:
{json.dumps(data, indent=2)}

Output:
{{
  "commentary": "short funny evaluation (1-3 sentences)"
}}
"""


# -------------------------
# CORE LOGIC: GENERATE QNA
# -------------------------
async def generate_qna():
    logger.info("CALLING GEMINI FOR QNA")

    raw = call_gemini(QNA_PROMPT)
    data = clean_json(raw)

    tasks = []
    for item in data["qna"]:
        tasks.append(generate_voice(item["red_response"]))
        tasks.append(generate_voice(item["blue_response"]))

    results = await asyncio.gather(*tasks)

    i = 0
    for item in data["qna"]:
        item["red_audio"] = results[i]
        item["blue_audio"] = results[i + 1]
        i += 2

    return data


# -------------------------
# CORE LOGIC: COMMENTARY
# -------------------------
async def generate_commentary(payload: dict):
    logger.info("CALLING GEMINI FOR COMMENTARY")

    prompt = build_eval_prompt(payload)
    raw = call_gemini(prompt)

    data = clean_json(raw)
    commentary = data.get("commentary", "No commentary")

    audio = await generate_voice(commentary)

    return commentary, audio


# -------------------------
# STARTUP
# -------------------------
@app.on_event("startup")
async def startup():
    global DATA
    try:
        DATA = await generate_qna()
        logger.info("STARTUP COMPLETE")
    except Exception as e:
        logger.error(f"STARTUP FAILED: {e}")
        DATA = {"qna": []}


# -------------------------
# API
# -------------------------
@app.post("/submit")
async def submit(payload: dict):
    try:
        logger.info(f"SUBMIT: {payload}")

        commentary, audio = await generate_commentary(payload)

        return {
            "commentary": commentary,
            "audio": audio
        }

    except Exception as e:
        logger.error(f"SUBMIT FAILED: {e}")
        return {
            "commentary": "Server error",
            "audio": ""
        }


@app.get("/qna")
def get_qna():
    return DATA


# -------------------------
# STATIC FILES
# -------------------------
app.mount("/audio", StaticFiles(directory="audio"), name="audio")
