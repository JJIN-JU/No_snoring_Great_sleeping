import os

from dotenv import load_dotenv
from pymongo import MongoClient

load_dotenv()

MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017")
MONGO_DB = os.getenv("MONGO_DB", "zzcare_db")

client = MongoClient(MONGO_URI)
db = client[MONGO_DB]

# 사용자 정보 컬렉션
users_collection = db["users"]

# 수면 관련 컬렉션
sleep_sessions = db["sleep_sessions"]
snore_events = db["snore_events"]
daily_stats = db["daily_stats"]


def create_indexes():
    users_collection.create_index(
        [("provider", 1), ("kakao_id", 1)],
        unique=True,
    )

    sleep_sessions.create_index("user_id")
    sleep_sessions.create_index("date")

    snore_events.create_index("user_id")
    snore_events.create_index("created_at")

    daily_stats.create_index(
        [("user_id", 1), ("date", 1)],
        unique=True,
    )


def check_db_connection():
    try:
        client.admin.command("ping")
        return True
    except Exception:
        return False


create_indexes()