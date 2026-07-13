from app.model_service import predict_batch
from app.feature import extract_librosa_binary_mfcc

import numpy as np
from pathlib import Path
import tempfile
import os

from pydub import AudioSegment #pydub 설치 필요
from app.config import (
    WINDOW_SECONDS,
    SEGMENT_SECONDS,
    SEGMENT_THRESHOLD,
    VOTE_THRESHOLD,
)

def split_audio(filepath: str):

    audio = AudioSegment.from_wav(filepath)

    temp_dir = tempfile.mkdtemp()

    segment_paths = []

    for i in range(WINDOW_SECONDS):

        start = start = i * SEGMENT_SECONDS * 1000
        end = (i + 1) * 1000

        segment = audio[start:end]

        segment_path = os.path.join(
            temp_dir,
            f"segment_{i}.wav"
        )

        segment.export(
            segment_path,
            format="wav"
        )

        segment_paths.append(segment_path)

    return segment_paths



def create_batch(segment_paths):

    mfcc_list = []

    for path in segment_paths:

        mfcc = extract_librosa_binary_mfcc(path)

        # (32,32) → (32,32,1)
        mfcc = np.expand_dims(mfcc, axis=-1)

        mfcc_list.append(mfcc)

    batch = np.stack(mfcc_list)

    return batch

def predict(filepath: str):

    # 1. 5초 → 1초 분할
    segment_paths = split_audio(filepath)

    # 2. Batch 생성
    batch = create_batch(segment_paths)

    # 3. Batch 추론
    probabilities = predict_batch(batch)

    # 4. Voting
    snore_count = int(np.sum(probabilities >= SEGMENT_THRESHOLD))

    is_snoring = snore_count >= VOTE_THRESHOLD

    return {
        "snoring": is_snoring,
        "snoring_probability": round(float(np.mean(probabilities)), 4),
        "snore_count": snore_count,

        # 기존 API 유지
        "has_noise": False,
        "noise": [],

        "segment_probability": probabilities.tolist(),
    }