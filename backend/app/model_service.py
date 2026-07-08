from pathlib import Path

import numpy as np
from tensorflow.keras.models import load_model

from app.feature import extract_librosa_mfcc

# =========모델 경로=========
BASE_DIR = Path(__file__).resolve().parent.parent
MODEL_DIR = BASE_DIR / "models"

# =========모델 로드=========
binary_model = load_model(MODEL_DIR / "librosa_binary_adam.keras")
multilabel_model = load_model(MODEL_DIR / "librosa_binary_adam_multi.keras")

# =========LABEL=========
LABELS = [
    "Snoring",
    "Baby",
    "Door",
    "Environmental",
    "Etc",
    "Toilet",
    "VoiceTV",
    "Vehicles",
    "Vibration",
    "WhiteNoise",
]
# =========Threshold=========
BINARY_THRESHOLD = 0.75
MULTI_THRESHOLDS = {
    "Snoring": 0.50,
    "Baby": 0.50,
    "Door": 0.50,
    "Environmental": 0.50,
    "Etc": 0.50,
    "Toilet": 0.50,
    "VoiceTV": 0.50,
    "Vehicles": 0.50,
    "Vibration": 0.50,
    "WhiteNoise": 0.50,
}

# =========모델=========
def predict(filepath: str) -> dict:

    # MFCC 생성
    mfcc = extract_librosa_mfcc(filepath)

    # (32,32) → (32,32,1)
    mfcc = np.expand_dims(mfcc, axis=-1)

    # (32,32,1) → (1,32,32,1)
    mfcc = np.expand_dims(mfcc, axis=0)


    # Binary Prediction
    binary_probability = float(
        binary_model.predict(
            mfcc,
            verbose=0
        )[0][0]
    )

    is_snoring = binary_probability >= BINARY_THRESHOLD


    # Multi-label Prediction
    multi_probability = multilabel_model.predict(
        mfcc,
        verbose=0
    )[0]

    detected_noise = []

    for label, prob in zip(LABELS, multi_probability):

        if prob >= MULTI_THRESHOLDS[label]:

            detected_noise.append({
                "label": label,
                "probability": round(float(prob), 4)
            })


    # Return
    return {
        "snoring": bool(is_snoring),
        "snoring_probability": float(binary_probability),
        "noise": detected_noise
    }
