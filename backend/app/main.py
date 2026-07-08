import os
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional
from uuid import uuid4

from fastapi import (
    FastAPI,
    HTTPException,
    UploadFile,
    File,
    Form,
)
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from app.database import (
    users_collection,
    sleep_sessions,
    snore_events,
    daily_stats,
)
from app.model_service import predict


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
# 업로드 파일 저장 폴더
# =========================

UPLOAD_DIR = Path("uploads/snore")
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


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

    return {
        "event_id": str(event["_id"]),
        "user_id": event.get("user_id"),
        "timestamp": event.get("timestamp"),
        "created_at": created_at,
        "snoring": event.get("snoring"),
        "snoring_probability": event.get("snoring_probability"),
        "has_noise": event.get("has_noise"),
        "noise": event.get("noise", []),
        "audio_path": event.get("audio_path"),
        "audio_filename": event.get("audio_filename"),
    }


def cleanup_old_snore_files():
    """
    MongoDB TTL은 DB 문서만 지움.
    서버에 저장된 오디오 파일은 별도로 7일 지난 파일을 삭제해야 함.
    """
    if not UPLOAD_DIR.exists():
        return

    cutoff = datetime.now(timezone.utc) - timedelta(days=7)

    for file_path in UPLOAD_DIR.iterdir():
        if not file_path.is_file():
            continue

        modified_at = datetime.fromtimestamp(
            file_path.stat().st_mtime,
            tz=timezone.utc,
        )

        if modified_at < cutoff:
            try:
                file_path.unlink()
            except Exception:
                pass


@app.get("/")
def root():
    return {
        "message": "ZZCare API is running"
    }


# =========================
# 카카오 로그인 / 회원 저장
# =========================

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
            "deleted_daily_stats": 0,
        }

    user_id = str(user["_id"])

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


# =========================
# 코골이 AI 예측 + DB 저장
# =========================

@app.post("/predict")
async def predict_audio(
    user_id: str = Form(...),
    timestamp: Optional[str] = Form(None),
    file: UploadFile = File(...),
):
    temp_path = None
    saved_path = None

    try:
        cleanup_old_snore_files()

        now = datetime.now(timezone.utc)
        timestamp_value = timestamp or now.isoformat()

        original_suffix = Path(file.filename or "").suffix.lower()

        if original_suffix not in [".wav", ".m4a", ".mp3", ".aac"]:
            original_suffix = ".wav"

        content = await file.read()

        if not content:
            raise HTTPException(
                status_code=400,
                detail="업로드된 오디오 파일이 비어 있습니다.",
            )

        # 1. AI 예측용 임시파일 생성
        with tempfile.NamedTemporaryFile(
            delete=False,
            suffix=original_suffix,
        ) as temp:
            temp.write(content)
            temp_path = temp.name

        # 2. AI 추론
        result = predict(temp_path)

        should_save = bool(result.get("snoring"))
        
        event_id = None
        saved = False
        audio_filename = None

        # 3. 코골이 또는 의미 있는 소음이 있는 경우만 DB + 서버 파일 저장
        if should_save:
            audio_filename = (
                f"snore_{now.strftime('%Y%m%d_%H%M%S')}_"
                f"{uuid4().hex}{original_suffix}"
            )
            saved_path = UPLOAD_DIR / audio_filename

            with open(saved_path, "wb") as out:
                out.write(content)

            doc = {
                "user_id": user_id,
                "timestamp": timestamp_value,

                # TTL 자동 삭제 기준.
                # 반드시 datetime 타입이어야 함.
                "created_at": now,

                "snoring": bool(result.get("snoring")),
                "snoring_probability": result.get("snoring_probability"),
                "has_noise": bool(result.get("has_noise")),
                "noise": result.get("noise", []),

                "audio_path": str(saved_path),
                "audio_filename": audio_filename,
            }

            insert_result = snore_events.insert_one(doc)
            event_id = str(insert_result.inserted_id)
            saved = True

        return {
            "success": True,
            "saved": saved,
            "event_id": event_id,
            "timestamp": timestamp_value,
            "audio_filename": audio_filename,
            **result,
        }

    except HTTPException:
        raise

    except Exception as e:
        # DB 저장 중 실패했고 파일이 만들어졌다면 정리
        if saved_path and os.path.exists(saved_path):
            try:
                os.remove(saved_path)
            except Exception:
                pass

        raise HTTPException(
            status_code=500,
            detail=str(e),
        )

    finally:
        if temp_path and os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except Exception:
                pass


@app.get("/snore-events/{user_id}")
def get_snore_events(user_id: str):
    """
    사용자의 최근 7일 코골이 이벤트 조회.
    TTL로 7일 지난 데이터는 자동 삭제됨.
    """
    events = list(
        snore_events.find(
            {"user_id": user_id}
        ).sort("created_at", -1)
    )

    return {
        "success": True,
        "count": len(events),
        "events": [
            event_to_response(event)
            for event in events
        ],
    }