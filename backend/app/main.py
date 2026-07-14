import os
import tempfile
import time
import traceback
from app import snore_detector as detector
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional
from uuid import uuid4

from bson import ObjectId
from fastapi import (
    FastAPI,
    HTTPException,
    UploadFile,
    File,
    Form,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from app.database import (
    users_collection,
    sleep_sessions,
    snore_events,
    daily_stats,
    snore_audio_fs,
)
from app.realtime_manager import realtime_manager
from app.config import SNORE_ALERT_COOLDOWN_SECONDS

app = FastAPI(
    title="ZZCare API",
    description="ZZCare 사용자 데이터 API",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# =========================
# 실시간/폴링 코골이 알림 설정
# =========================

last_snore_alert_time = 0

latest_snore_alert_id = 0
latest_snore_alert = None


def create_latest_snore_alert(
    title: str = "코골이 감지",
    message: str = "코골이가 감지되었습니다. 자세를 바꿔보세요.",
    snore_score: float = 0.95,
):
    global latest_snore_alert_id
    global latest_snore_alert

    latest_snore_alert_id += 1

    latest_snore_alert = {
        "id": latest_snore_alert_id,
        "type": "SNORE_ALERT",
        "snoring": True,
        "title": title,
        "message": message,
        "level": "WARNING",
        "vibration": True,
        "snore_score": snore_score,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    print(f"[SNORE_ALERT_CREATED] id={latest_snore_alert_id}")

    return latest_snore_alert


class KakaoLoginRequest(BaseModel):
    kakao_id: str
    nickname: Optional[str] = None
    email: Optional[str] = None
    profile_image_url: Optional[str] = None


def user_to_response(user: dict):
    return {
        "user_id": str(user["_id"]),
        "provider": user.get("provider"),
        "kakao_id": user.get("kakao_id"),
        "nickname": user.get("nickname"),
        "email": user.get("email"),
        "profile_image_url": user.get("profile_image_url"),
        "created_at": user.get("created_at"),
        "last_login_at": user.get("last_login_at"),
    }


def event_to_response(event: dict):
    created_at = event.get("created_at")

    if isinstance(created_at, datetime):
        created_at = created_at.isoformat()

    audio_file_id = event.get("audio_file_id")

    return {
        "event_id": str(event["_id"]),
        "user_id": event.get("user_id"),
        "timestamp": event.get("timestamp"),
        "created_at": created_at,
        "snoring": event.get("snoring"),
        "snoring_probability": event.get("snoring_probability"),
        "has_noise": event.get("has_noise"),
        "noise": event.get("noise", []),

        # 5초 → 1초 5개 투표 결과
        "snore_count": event.get("snore_count"),
        "segment_count": event.get("segment_count"),
        "vote_required": event.get("vote_required"),
        "segment_probability": event.get("segment_probability", []),
        "segments": event.get("segments", []),

        # 새 구조
        "audio_storage": event.get("audio_storage"),
        "audio_file_id": audio_file_id,
        "audio_filename": event.get("audio_filename"),
        "audio_url": (
            f"/snore-events/audio/{audio_file_id}"
            if audio_file_id
            else None
        ),

        # 예전 구조 호환용
        "audio_path": event.get("audio_path"),
    }


def cleanup_old_snore_audio_files():
    """
    GridFS에 저장된 7일 지난 오디오 파일 삭제.
    snore_events는 TTL로 삭제되고, GridFS 오디오는 여기서 직접 삭제한다.
    """

    cutoff = datetime.now(timezone.utc) - timedelta(days=7)
    cutoff_naive = cutoff.replace(tzinfo=None)

    try:
        old_files = snore_audio_fs.find(
            {
                "uploadDate": {
                    "$lt": cutoff_naive,
                }
            }
        )

        deleted_count = 0

        for grid_file in old_files:
            try:
                snore_audio_fs.delete(grid_file._id)
                deleted_count += 1
            except Exception:
                pass

        if deleted_count > 0:
            print(f"[GRIDFS_CLEANUP] deleted={deleted_count}")

    except Exception as e:
        print(f"[GRIDFS_CLEANUP_FAILED] {e}")


def delete_gridfs_audio_file(audio_file_id: str) -> bool:
    try:
        object_id = ObjectId(audio_file_id)
    except Exception:
        return False

    try:
        if snore_audio_fs.exists(object_id):
            snore_audio_fs.delete(object_id)
            return True
    except Exception:
        return False

    return False


def normalize_detector_result(result: dict) -> dict:
    """
    snore_detector.py의 결과를 기존 main.py / Flutter가 쓰던 응답 형식에 맞춘다.
    snore_detector.py 자체는 그대로 둬도 된다.
    
    기존 snore_detector.py 반환 예:
    {
        "snoring": true,
        "snore_count": 3,
        "segment_probability": [0.8, 0.7, 0.1, 0.9, 0.2]
    }
    """

    segment_probability = result.get("segment_probability", [])

    if isinstance(segment_probability, list):
        cleaned_probabilities = []

        for value in segment_probability:
            try:
                cleaned_probabilities.append(round(float(value), 4))
            except Exception:
                cleaned_probabilities.append(0.0)
    else:
        cleaned_probabilities = []

    segment_count = len(cleaned_probabilities)

    try:
        snore_count = int(result.get("snore_count") or 0)
    except Exception:
        snore_count = 0

    vote_required = int(result.get("vote_required") or 3)
    is_snoring = bool(result.get("snoring"))

    max_probability = (
        max(cleaned_probabilities)
        if cleaned_probabilities
        else 0.0
    )

    avg_probability = (
        sum(cleaned_probabilities) / len(cleaned_probabilities)
        if cleaned_probabilities
        else 0.0
    )

    segments = []

    for index, probability in enumerate(cleaned_probabilities):
        segments.append(
            {
                "index": index,
                "start_second": index,
                "end_second": index + 1,
                "snoring_probability": probability,
                "snoring": probability >= 0.50,
            }
        )

    return {
        **result,

        # 기존 코드 호환용 필드
        "snoring": is_snoring,
        "snoring_detected": is_snoring,
        "snoring_probability": round(max_probability, 4),
        "max_snoring_probability": round(max_probability, 4),
        "avg_snoring_probability": round(avg_probability, 4),
        "has_noise": is_snoring,
        "noise": [
            {
                "label": "Snoring",
                "probability": round(max_probability, 4),
            }
        ] if is_snoring else [],

        # 투표 결과 필드
        "segment_count": segment_count,
        "snore_count": snore_count,
        "vote_required": vote_required,
        "segment_probability": cleaned_probabilities,
        "segments": segments,
    }


def result_has_snoring(result: dict) -> bool:
    """
    snore_detector.py의 5초 → 1초 5개 투표 결과를 최우선으로 사용한다.
    """

    if "snore_count" in result and "segment_count" in result:
        return bool(result.get("snoring"))

    if bool(result.get("snoring")):
        return True

    if bool(result.get("snoring_detected")):
        return True

    try:
        probability = float(result.get("snoring_probability") or 0)
    except Exception:
        probability = 0

    return probability >= 0.50


def get_snore_score(result: dict) -> float:
    try:
        return float(result.get("snoring_probability") or 0)
    except Exception:
        return 0.0


async def create_snore_alert_if_needed(result: dict):
    global last_snore_alert_time

    is_snoring = result_has_snoring(result)

    if not is_snoring:
        return {
            "created": False,
            "reason": "not_snoring",
            "alert_id": None,
            "websocket_sent_count": 0,
        }

    now_time = time.time()

    if now_time - last_snore_alert_time < SNORE_ALERT_COOLDOWN_SECONDS:
        return {
            "created": False,
            "reason": "cooldown",
            "alert_id": latest_snore_alert_id,
            "websocket_sent_count": 0,
        }

    last_snore_alert_time = now_time

    snore_score = get_snore_score(result)

    alert = create_latest_snore_alert(
        title="코골이 감지",
        message="코골이가 감지되었습니다. 자세를 바꿔보세요.",
        snore_score=snore_score,
    )

    sent_count = 0

    try:
        sent_count = await realtime_manager.broadcast(alert)
    except Exception as e:
        print(f"[WS_BROADCAST_FAILED] {e}")

    return {
        "created": True,
        "reason": "created",
        "alert_id": alert["id"],
        "websocket_sent_count": sent_count,
    }


@app.get("/")
def root():
    return {
        "message": "ZZCare API is running",
    }


@app.websocket("/ws/snore")
async def snore_websocket(websocket: WebSocket):
    await realtime_manager.connect(websocket)

    try:
        while True:
            await websocket.receive_text()

    except WebSocketDisconnect:
        realtime_manager.disconnect(websocket)

    except Exception:
        realtime_manager.disconnect(websocket)


@app.post("/test/snore-alert")
async def test_snore_alert():
    alert = create_latest_snore_alert(
        title="코골이 감지 테스트",
        message="FastAPI에서 보낸 테스트 코골이 알림입니다.",
        snore_score=0.95,
    )

    sent_count = 0

    try:
        sent_count = await realtime_manager.broadcast(alert)
    except Exception as e:
        print(f"[WS_BROADCAST_FAILED] {e}")

    return {
        "ok": True,
        "message": "코골이 테스트 알림 생성 완료",
        "alert_id": alert["id"],
        "websocket_sent_count": sent_count,
    }


@app.get("/alerts/snore/latest")
def get_latest_snore_alert(last_id: int = 0):
    has_new = (
        latest_snore_alert is not None
        and latest_snore_alert_id > last_id
    )

    return {
        "success": True,
        "current_id": latest_snore_alert_id,
        "has_new": has_new,
        "alert": latest_snore_alert if has_new else None,
    }


@app.post("/auth/kakao")
def save_kakao_user(payload: KakaoLoginRequest):
    if not payload.kakao_id:
        raise HTTPException(
            status_code=400,
            detail="kakao_id가 필요합니다.",
        )

    now = datetime.now(timezone.utc).isoformat()

    users_collection.update_one(
        {
            "provider": "kakao",
            "kakao_id": payload.kakao_id,
        },
        {
            "$set": {
                "nickname": payload.nickname,
                "email": payload.email,
                "profile_image_url": payload.profile_image_url,
                "last_login_at": now,
            },
            "$setOnInsert": {
                "provider": "kakao",
                "kakao_id": payload.kakao_id,
                "created_at": now,
            },
        },
        upsert=True,
    )

    user = users_collection.find_one(
        {
            "provider": "kakao",
            "kakao_id": payload.kakao_id,
        }
    )

    if user is None:
        raise HTTPException(
            status_code=500,
            detail="사용자 저장 후 조회에 실패했습니다.",
        )

    return {
        "success": True,
        "user": user_to_response(user),
    }


@app.delete("/auth/kakao/{kakao_id}")
def delete_kakao_user(kakao_id: str):
    user = users_collection.find_one(
        {
            "provider": "kakao",
            "kakao_id": kakao_id,
        }
    )

    if user is None:
        return {
            "success": True,
            "message": "이미 삭제된 사용자입니다.",
            "deleted_user": 0,
            "deleted_sleep_sessions": 0,
            "deleted_snore_events": 0,
            "deleted_snore_audio_files": 0,
            "deleted_daily_stats": 0,
        }

    user_id = str(user["_id"])

    snore_event_docs = list(
        snore_events.find(
            {"user_id": user_id},
            {"audio_file_id": 1},
        )
    )

    audio_file_ids = {
        str(doc.get("audio_file_id"))
        for doc in snore_event_docs
        if doc.get("audio_file_id")
    }

    deleted_snore_audio_files = 0

    for audio_file_id in audio_file_ids:
        if delete_gridfs_audio_file(audio_file_id):
            deleted_snore_audio_files += 1

    deleted_sleep_sessions = sleep_sessions.delete_many(
        {"user_id": user_id}
    ).deleted_count

    deleted_snore_events = snore_events.delete_many(
        {"user_id": user_id}
    ).deleted_count

    deleted_daily_stats = daily_stats.delete_many(
        {"user_id": user_id}
    ).deleted_count

    deleted_user = users_collection.delete_one(
        {
            "provider": "kakao",
            "kakao_id": kakao_id,
        }
    ).deleted_count

    return {
        "success": True,
        "message": "회원 정보가 삭제되었습니다.",
        "deleted_user": deleted_user,
        "deleted_sleep_sessions": deleted_sleep_sessions,
        "deleted_snore_events": deleted_snore_events,
        "deleted_snore_audio_files": deleted_snore_audio_files,
        "deleted_daily_stats": deleted_daily_stats,
    }


@app.get("/users")
def get_users():
    users = list(
        users_collection.find().sort("last_login_at", -1)
    )

    return {
        "count": len(users),
        "users": [
            user_to_response(user)
            for user in users
        ],
    }

@app.post("/predict")
async def predict_audio(
    user_id: str = Form(...),
    timestamp: Optional[str] = Form(None),
    save: bool = Form(True),
    file: UploadFile = File(...)
):
    temp_path = None

    try:
        now = datetime.now(timezone.utc)
        timestamp_value = timestamp or now.isoformat()

        # 업로드한 wav를 임시 저장
        with tempfile.NamedTemporaryFile(
            delete=False,
            suffix=".wav"
        ) as temp:
            temp.write(await file.read())
            temp_path = temp.name

        # AI 추론
        raw_result = detector.predict(temp_path)
        result = normalize_detector_result(raw_result)

        # 코골이 또는 잡음이 있는 경우만 저장
        # 실시간 판별(save=false)은 DB 저장 없이 응답만 반환
        if save and (result["snoring"] or result["has_noise"]):
            snore_events.insert_one({
                "user_id": user_id,
                "timestamp": timestamp_value,
                "snoring": result["snoring"],
                "created_at": now.isoformat(),
                "snoring_probability": result["snoring_probability"],
                "has_noise": result["has_noise"],
                "noise": result["noise"],
                "snore_count": result.get("snore_count"),
                "segment_count": result.get("segment_count"),
                "vote_required": result.get("vote_required"),
                "segment_probability": result.get("segment_probability", []),
                "segments": result.get("segments", []),
            })

        return {
            **result,
            "timestamp": timestamp_value,
        }

    except Exception as e:
        traceback.print_exc()
        raise HTTPException(
            status_code=500,
            detail=str(e)
        )

    finally:
        if temp_path and os.path.exists(temp_path):
            os.remove(temp_path)