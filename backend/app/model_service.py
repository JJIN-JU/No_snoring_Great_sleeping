from pathlib import Path

import numpy as np
import tensorflow as tf
from tensorflow.keras.models import load_model

from app.feature import extract_librosa_binary_mfcc

from app.config import (
    MODEL_DIR,
    BINARY_MODEL_NAME,
    MULTILABEL_MODEL_NAME,
    LABELS,
    BINARY_THRESHOLD,
    MULTI_THRESHOLDS,
)

binary_model = load_model(
    MODEL_DIR / BINARY_MODEL_NAME
)

multilabel_model = load_model(
    MODEL_DIR / MULTILABEL_MODEL_NAME
)

def prepare_mfcc_for_model(mfcc) -> np.ndarray:

    x = np.asarray(mfcc, dtype=np.float32)

    # 예:
    # (1, 40, 174, 1) -> (40, 174)
    # (40, 174, 1)    -> (40, 174)
    # (40, 174)       -> 그대로
    x = np.squeeze(x)

    if x.ndim != 2:
        raise ValueError(
            f"MFCC 전처리 실패: 2차원 배열이 필요하지만 현재 shape={x.shape}"
        )

    # (40, 174) 같은 MFCC를 모델 입력 크기인 (32, 32)로 리사이즈
    x = x[..., np.newaxis]  # (H, W, 1)

    x = tf.image.resize(
        x,
        size=(32, 32),
    ).numpy()

    # 최종 모델 입력: (1, 32, 32, 1)
    x = np.expand_dims(x, axis=0)

    return x.astype(np.float32)


def predict(filepath: str) -> dict:
    # 1. MFCC 생성
    mfcc = extract_librosa_binary_mfcc(filepath)

    # 2. 모델 입력 shape로 변환
    mfcc = prepare_mfcc_for_model(mfcc)

    # 3. Binary Prediction
    binary_probability = float(
        binary_model.predict(
            mfcc,
            verbose=0,
        )[0][0]
    )

    is_snoring = binary_probability >= BINARY_THRESHOLD

    # 4. Multi-label Prediction
    multi_probability = multilabel_model.predict(
        mfcc,
        verbose=0,
    )[0]

    detected_noise = []

    for label, prob in zip(LABELS, multi_probability):
        if prob >= MULTI_THRESHOLDS[label]:
            detected_noise.append(
                {
                    "label": label,
                    "probability": round(float(prob), 4),
                }
            )

    return {
        "snoring": bool(is_snoring),
        "snoring_probability": round(float(binary_probability), 4),
        "has_noise": len(detected_noise) > 0,
        "noise": detected_noise,
    }

def predict_batch(batch):

    probability = binary_model.predict(
        batch,
        verbose=0
    ).reshape(-1)

    return probability