import os
from dotenv import load_dotenv
from pymongo import MongoClient

load_dotenv()

MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017")
MONGO_DB = os.getenv("MONGO_DB", "zzcare_db")

client = MongoClient(MONGO_URI)
db = client[MONGO_DB]

sleep_sessions = db["sleep_sessions"]
snore_events = db["snore_events"]
daily_stats = db["daily_stats"]


def check_db_connection():
    try:
        client.admin.command("ping")
        return True
    except Exception:
        return False