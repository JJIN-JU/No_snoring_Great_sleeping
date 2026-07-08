import numpy as np
import librosa


def extract_librosa_mfcc(
    audio_path: str,
    sr: int = 22050,
    n_mfcc: int = 40,
    max_pad_len: int = 174,
):
    """
    코골이 오디오 파일에서 Librosa MFCC 특징을 추출합니다.

    반환 shape:
    (1, 40, 174, 1)

    Keras CNN 모델 입력용
    """

    # 오디오 로드
    y, sr = librosa.load(audio_path, sr=sr, mono=True)

    # 너무 짧은 오디오 방어
    if y is None or len(y) == 0:
        raise ValueError("오디오 파일을 읽을 수 없거나 비어 있습니다.")

    # MFCC 추출
    mfcc = librosa.feature.mfcc(
        y=y,
        sr=sr,
        n_mfcc=n_mfcc,
    )

    # 길이 맞추기
    if mfcc.shape[1] < max_pad_len:
        pad_width = max_pad_len - mfcc.shape[1]
        mfcc = np.pad(
            mfcc,
            pad_width=((0, 0), (0, pad_width)),
            mode="constant",
        )
    else:
        mfcc = mfcc[:, :max_pad_len]

    # 정규화
    mfcc = mfcc.astype(np.float32)

    # 모델 입력 shape로 변환
    mfcc = np.expand_dims(mfcc, axis=0)   # (1, 40, 174)
    mfcc = np.expand_dims(mfcc, axis=-1)  # (1, 40, 174, 1)

    return mfcc