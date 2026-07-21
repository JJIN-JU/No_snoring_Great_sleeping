from __future__ import annotations

import json
import os
from typing import Literal

from dotenv import load_dotenv
from fastapi import APIRouter, HTTPException
from fastapi.concurrency import run_in_threadpool
from openai import OpenAI
from pydantic import BaseModel, Field


load_dotenv()


router = APIRouter(
    prefix="/sleep-tags",
    tags=["sleep-tags"],
)


# =========================================================
# LLM 서버 상태 확인
# =========================================================

@router.get("/health")
def sleep_llm_health():
    """
    수면 태그 LLM API의 연결 상태와
    환경변수 설정 여부를 확인한다.

    실제 API 키 값은 외부로 반환하지 않는다.
    """

    return {
        "success": True,
        "service": "sleep-tag-llm",
        "api_key_configured": bool(
            os.getenv("OPENAI_API_KEY")
        ),
        "model": os.getenv(
            "OPENAI_MODEL",
            "gpt-5-mini",
        ),
    }


# =========================================================
# Flutter 앱에서 전달받는 데이터
# =========================================================

class SleepMetrics(BaseModel):
    analysis_period: str

    record_count: int = Field(ge=0)
    sleep_record_count: int = Field(ge=0)
    snore_record_count: int = Field(ge=0)

    average_sleep_hours: float = Field(ge=0)
    target_sleep_hours: float = Field(ge=0)

    average_bedtime: str
    average_wake_time: str

    snore_days: int = Field(ge=0)
    total_snore_count: int = Field(ge=0)
    total_snore_hours: float = Field(ge=0)

    average_snore_ratio: float = Field(
        ge=0,
        le=100,
    )


class SleepTagInput(BaseModel):
    name: str

    severity: Literal[
        "good",
        "caution",
        "attention",
    ]

    description: str
    evidence: list[str]


class SleepLlmRequest(BaseModel):
    metrics: SleepMetrics
    tags: list[SleepTagInput]


# =========================================================
# LLM이 반환할 구조
# =========================================================

class SleepTagAdvice(BaseModel):
    tag_name: str

    personalized_interpretation: str = Field(
        min_length=20,
        max_length=350,
    )

    recommendations: list[str] = Field(
        min_length=3,
        max_length=3,
    )

    weekly_goal: str = Field(
        min_length=10,
        max_length=180,
    )


class SleepLlmResponse(BaseModel):
    overall_summary: str = Field(
        min_length=30,
        max_length=600,
    )

    tag_advices: list[SleepTagAdvice]

    weekly_goals: list[str] = Field(
        min_length=2,
        max_length=3,
    )

    caution_note: str = Field(
        min_length=20,
        max_length=300,
    )


SYSTEM_PROMPT = """
당신은 사용자의 실제 수면 기록과 코골이 기록을 바탕으로
개인 맞춤형 생활 습관 개선 방법을 작성하는 한국어 수면 관리 코치입니다.

입력으로 전달된 수치와 분석 근거만 사용해야 합니다.

반드시 지켜야 할 규칙:

1. 입력에 없는 질환, 증상, 수치 또는 생활 습관을 추측하지 마세요.
2. 입력된 태그 이름을 변경하지 마세요.
3. 새로운 태그를 임의로 추가하지 마세요.
4. 각 입력 태그마다 반드시 정확히 3개의 개선 방법을 작성하세요.
5. 개선 방법은 사용자의 실제 시간, 횟수, 부족 시간 또는 패턴을 반영하세요.
6. 각 태그의 개선 방법 중 최소 2개에는 사용자의 실제 수치나 시간 차이를 활용하세요.
7. 매번 같은 일반적인 문장을 반복하지 마세요.
8. '일찍 자세요', '규칙적으로 생활하세요'와 같은 모호한 문장만 작성하지 마세요.
9. 오늘부터 실행할 수 있도록 시간, 횟수, 기간이 포함된 구체적인 행동으로 작성하세요.
10. 목표를 한 번에 지나치게 변경하지 말고 단계적인 목표를 제시하세요.
11. 약 복용, 치료, 수술 또는 의료 행위를 직접 지시하지 마세요.
12. 질환이나 수면무호흡증을 진단하거나 단정하지 마세요.
13. 코골이와 숨 멈춤, 헐떡임, 심한 주간 졸림 등이 반복되는 경우에만
    전문가 상담을 고려하도록 조건부로 안내하세요.
14. 공포감을 주거나 과장된 표현을 사용하지 마세요.
15. weekly_goal과 weekly_goals에는 횟수, 시간 또는 기간이 들어가야 합니다.
16. 모든 결과는 자연스럽고 이해하기 쉬운 한국어로 작성하세요.
17. 본 분석이 의료 진단이 아니라 생활 습관 관리용 참고 자료임을 명시하세요.

좋지 않은 예:
- 일찍 자세요.
- 건강한 생활을 하세요.
- 규칙적으로 생활하세요.

좋은 예:
- 평균 취침 시간이 오전 1시 20분이므로 이번 주 3일은
  오전 1시 이전에 잠자리에 들어보세요.
- 주말 기상 시간이 평일보다 1시간 45분 늦다면,
  이번 주말에는 차이를 1시간 15분 이내로 줄여보세요.
"""


def _create_sleep_analysis(
    request_data: SleepLlmRequest,
) -> SleepLlmResponse:
    api_key = os.getenv("OPENAI_API_KEY")

    if not api_key:
        raise RuntimeError(
            "OPENAI_API_KEY 환경변수가 설정되지 않았습니다."
        )

    model = os.getenv(
        "OPENAI_MODEL",
        "gpt-5-mini",
    )

    client = OpenAI(
        api_key=api_key,
    )

    payload_text = json.dumps(
        request_data.model_dump(),
        ensure_ascii=False,
        indent=2,
    )

    response = client.responses.parse(
        model=model,
        input=[
            {
                "role": "system",
                "content": SYSTEM_PROMPT,
            },
            {
                "role": "user",
                "content": (
                    "다음 수면 분석 데이터를 바탕으로 "
                    "사용자 개인 맞춤형 종합 의견, 태그별 해석, "
                    "개선 방법과 이번 주 실천 목표를 작성하세요.\n\n"
                    f"{payload_text}"
                ),
            },
        ],
        text_format=SleepLlmResponse,
    )

    result = response.output_parsed

    if result is None:
        raise RuntimeError(
            "LLM 응답을 구조화된 결과로 변환하지 못했습니다."
        )

    requested_names = [
        tag.name
        for tag in request_data.tags
    ]

    returned_names = [
        advice.tag_name
        for advice in result.tag_advices
    ]

    if len(requested_names) != len(returned_names):
        raise RuntimeError(
            "LLM이 일부 태그의 분석 결과를 반환하지 않았습니다."
        )

    if set(requested_names) != set(returned_names):
        raise RuntimeError(
            "LLM이 입력과 다른 수면 태그를 반환했습니다."
        )

    for advice in result.tag_advices:
        if len(advice.recommendations) != 3:
            raise RuntimeError(
                f"{advice.tag_name}의 개선 방법이 3개가 아닙니다."
            )

        cleaned_recommendations = [
            recommendation.strip()
            for recommendation in advice.recommendations
            if recommendation.strip()
        ]

        if len(cleaned_recommendations) != 3:
            raise RuntimeError(
                f"{advice.tag_name}에 비어 있는 개선 방법이 포함되어 있습니다."
            )

        advice.recommendations = cleaned_recommendations

    cleaned_weekly_goals = [
        goal.strip()
        for goal in result.weekly_goals
        if goal.strip()
    ]

    if len(cleaned_weekly_goals) < 2:
        raise RuntimeError(
            "LLM이 충분한 주간 실천 목표를 반환하지 않았습니다."
        )

    result.weekly_goals = cleaned_weekly_goals

    return result


@router.post(
    "/llm-analysis",
    response_model=SleepLlmResponse,
)
async def generate_sleep_llm_analysis(
    request_data: SleepLlmRequest,
):
    if not request_data.tags:
        raise HTTPException(
            status_code=400,
            detail="분석할 수면 태그가 없습니다.",
        )

    if request_data.metrics.record_count <= 0:
        raise HTTPException(
            status_code=400,
            detail="분석할 수면 기록이 없습니다.",
        )

    try:
        return await run_in_threadpool(
            _create_sleep_analysis,
            request_data,
        )

    except HTTPException:
        raise

    except Exception as error:
        print(
            "[SLEEP LLM ERROR]",
            repr(error),
        )

        raise HTTPException(
            status_code=502,
            detail=(
                "AI 맞춤 수면 분석을 생성하지 못했습니다. "
                "백엔드 로그와 OpenAI API 키를 확인해 주세요."
            ),
        ) from error