import os

import gridfs
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

# 코골이 오디오 파일 자체 저장용 GridFS
# MongoDB Compass에서는 snore_audio.files / snore_audio.chunks 로 보임
snore_audio_fs = gridfs.GridFS(db, collection="snore_audio")


def ensure_snore_events_ttl_index():
    """
    snore_events.created_at 기준 7일 TTL 인덱스 생성.
    기존 created_at 일반 인덱스가 있으면 삭제 후 TTL 인덱스로 다시 생성.
    """

    target_index_name = "snore_events_7days_ttl"
    ttl_seconds = 60 * 60 * 24 * 7

    indexes = list(snore_events.list_indexes())

    for index in indexes:
        index_name = index.get("name")
        key = list(index.get("key", {}).items())

        is_created_at_index = key == [("created_at", 1)]

        if not is_created_at_index:
            continue

        expire_after = index.get("expireAfterSeconds")

        if index_name == target_index_name and expire_after == ttl_seconds:
            return

        snore_events.drop_index(index_name)

    snore_events.create_index(
        "created_at",
        expireAfterSeconds=ttl_seconds,
        name=target_index_name,
    )


def create_indexes():
    users_collection.create_index(
        [("provider", 1), ("kakao_id", 1)],
        unique=True,
    )

    sleep_sessions.create_index("user_id")
    sleep_sessions.create_index("date")

    snore_events.create_index("user_id")
    snore_events.create_index("audio_file_id")

    ensure_snore_events_ttl_index()

    daily_stats.create_index(
        [("user_id", 1), ("date", 1)],
        unique=True,
    )

    # GridFS 파일 조회용 인덱스
    db["snore_audio.files"].create_index("metadata.user_id")
    db["snore_audio.files"].create_index("uploadDate")


def check_db_connection():
    try:
        client.admin.command("ping")
        return True
    except Exception:
        return False


create_indexes()