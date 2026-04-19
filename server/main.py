from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
import requests
import json
import os
import uuid
import edge_tts
import asyncio
import html
import logging

app = FastAPI()

API_KEY = "AIzaSyCyugDeWAHBC2PZryTl0gy7crBa8SNwrNE"

URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/"
    "gemini-2.5-flash-lite:generateContent?key=" + API_KEY
)

DATA = None

AUDIO_DIR = "audio"
os.makedirs(AUDIO_DIR, exist_ok=True)

# -------------------------
# LOGGING
# -------------------------
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("tts")

# limit concurrency (prevents Edge TTS crashes)
sem = asyncio.Semaphore(5)

# -------------------------
# CLEAN AUDIO FOLDER
# -------------------------


def clear_audio_folder():
    for f in os.listdir(AUDIO_DIR):
        path = os.path.join(AUDIO_DIR, f)
        if os.path.isfile(path):
            os.remove(path)

# -------------------------
# CLEAN GEMINI JSON
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
# TTS GENERATION
# -------------------------


async def generate_voice(text: str,) -> str:
    async with sem:
        try:
            id = uuid.uuid4()
            logger.info(f"TTS START | ID = {id}")

            filename = f"{id}.mp3"
            path = os.path.join(AUDIO_DIR, filename)

            communicate = edge_tts.Communicate(
                text=text,
                voice="en-US-BrianMultilingualNeural",
            )

            await communicate.save(path)

            logger.info(f"TTS DONE | file={filename}")

            return "/audio/" + filename

        except Exception as e:
            logger.error(f"TTS FAILED | Id ={id} | error={e}")
            return ""

# -------------------------
# GEMINI PROMPT
# -------------------------
prompt = """
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
      "blue_response": "",
    }
  ]
}
"""

# -------------------------
# GENERATE QNA + TTS
# -------------------------


async def generate_qna():
    payload = {
        "contents": [
            {"parts": [{"text": prompt}]}
        ]
    }

    logger.info("CALLING GEMINI")

    res = requests.post(URL, json=payload)
    text = res.json()["candidates"][0]["content"]["parts"][0]["text"]

    data = clean_json(text)

    logger.info("GEMINI DATA RECEIVED")

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
# STARTUP
# -------------------------


@app.on_event("startup")
async def startup():
    global DATA
    try:
        clear_audio_folder()
        logger.info("STARTUP: generating QNA")
        DATA = await generate_qna()
        logger.info("STARTUP: READY")

    except Exception as e:
        logger.error(f"STARTUP FAILED: {e}")
        DATA = {"qna": []}

# -------------------------
# API
# -------------------------


@app.get("/qna")
def get_qna():
    return DATA


# -------------------------
# STATIC AUDIO
# -------------------------
app.mount("/audio", StaticFiles(directory="audio"), name="audio")
