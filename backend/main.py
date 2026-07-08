import tempfile
import os

from datetime import datetime, timezone
from typing import Optional

from fastapi import (
    FastAPI,
    HTTPException,
    UploadFile,
    File,
)
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from app.database import users_collection
from app.model_service import predict

from app.database import (
    users_collection,
    sleep_sessions,
    snore_events,
    daily_stats,
)

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


@app.get("/")
def root():
    return {
        "message": "ZZCare API is running"
    }


@app.post("/auth/kakao")
def save_kakao_user(payload: KakaoLoginRequest):
    if not payload.kakao_id:
        raise HTTPException(
            status_code=400,
            detail="kakao_id가 필요합니다."
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
            detail="사용자 저장 후 조회에 실패했습니다."
        )

    return {
        "success": True,
        "user": user_to_response(user),
    }

@app.delete("/auth/kakao/{kakao_id}")
def delete_kakao_user(kakao_id: str):
    user = users_collection.find_one(
        {"provider": "kakao", "kakao_id": kakao_id}
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
        {"provider": "kakao", "kakao_id": kakao_id}
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
    users = list(users_collection.find().sort("last_login_at", -1))

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
    file: UploadFile = File(...)
):

    temp_path = None

    try:

        # 업로드한 wav를 임시 저장
        with tempfile.NamedTemporaryFile(
            delete=False,
            suffix=".wav"
        ) as temp:

            temp.write(await file.read())
            temp_path = temp.name

        # AI 추론
        result = predict(temp_path)

        # 코골이 또는 잡음이 있는 경우만 저장
        if result["snoring"] or result["has_noise"]:

            snore_events.insert_one({

                "user_id": user_id,

                "timestamp": timestamp or datetime.now(timezone.utc).isoformat(),

                "snoring": result["snoring"],

                "created_at": datetime.now(timezone.utc).isoformat(),

                "snoring_probability": result["snoring_probability"],

                "has_noise": result["has_noise"],

                "noise": result["noise"]

            })

        return {
            **result,
            "timestamp": timestamp or now}
            
    except Exception as e:

        raise HTTPException(
            status_code=500,
            detail=str(e)
        )

    finally:

        if temp_path and os.path.exists(temp_path):
            os.remove(temp_path)