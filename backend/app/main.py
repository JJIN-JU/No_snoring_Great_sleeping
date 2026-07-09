import os
import tempfile
import time
import traceback
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
    WebSocket,
    WebSocketDisconnect,
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
from app.realtime_manager import realtime_manager


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
SNORE_ALERT_COOLDOWN_SECONDS = 30

latest_snore_alert_id = 0
latest_snore_alert = None


def create_latest_snore_alert(
    title: str = "코골이 감지",
    message: str = "코골이가 감지되었습니다. 자세를 바꿔보세요.",
    snore_score: float = 0.95,
):
    """
    Flutter 앱이 polling으로 가져갈 최신 알림 생성.
    """
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


def result_has_snoring(result: dict) -> bool:
    """
    binary 모델 결과, multi-label Snoring 라벨, 확률값을 모두 고려해서
    최종적으로 코골이 여부를 판단한다.
    """
    if bool(result.get("snoring")):
        return True

    noise = result.get("noise", [])

    if isinstance(noise, list):
        for item in noise:
            if not isinstance(item, dict):
                continue

            label = str(item.get("label", "")).lower()

            if label == "snoring":
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
    """
    코골이 감지 시 최신 알림 생성.
    WebSocket은 실패해도 괜찮고, Flutter polling이 /alerts/snore/latest로 가져감.
    """
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
        "message": "ZZCare API is running"
    }


# =========================
# WebSocket 실시간 연결
# =========================

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


# =========================
# 테스트 알림 / 폴링 API
# =========================

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
# 코골이 AI 예측 + DB 저장 + 알림 생성
# =========================

@app.post("/predict")
async def predict_audio(
    user_id: str = Form(...),
    timestamp: Optional[str] = Form(None),
    save: bool = Form(True),
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

        # 3. 코골이 여부 판단
        should_save = result_has_snoring(result)

        # 4. 코골이면 최신 알림 생성
        alert_info = await create_snore_alert_if_needed(result)

        event_id = None
        saved = False
        audio_filename = None

        # 5. save=true이고, AI가 코골이라고 판단한 경우만 DB + 서버 파일 저장
        if save and should_save:
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
                "created_at": now,
                "snoring": bool(should_save),
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
            "snoring_detected": should_save,
            "realtime_alert_created": alert_info["created"],
            "alert_reason": alert_info["reason"],
            "alert_id": alert_info["alert_id"],
            "websocket_sent_count": alert_info["websocket_sent_count"],
            **result,
        }

    except HTTPException:
        raise

    except Exception:
        traceback.print_exc()

        if saved_path and os.path.exists(saved_path):
            try:
                os.remove(saved_path)
            except Exception:
                pass

        raise HTTPException(
            status_code=500,
            detail=traceback.format_exc(),
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