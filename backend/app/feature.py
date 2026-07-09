import numpy as np
import librosa


def extract_librosa_binary_mfcc(filepath):

    signal, sr = librosa.load(
        filepath,
        sr=None,
        mono=True
    )

    mfcc = librosa.feature.mfcc(
        y=signal,
        sr=sr,
        n_mfcc=32,
        n_fft=512,
    )

    # 길이 맞추기
    if mfcc.shape[1] < 32:
        pad = 32 - mfcc.shape[1]
        mfcc = np.pad(mfcc, ((0, 0), (0, pad)), mode="constant")
    else:
        mfcc = mfcc[:, :32]

    return mfcc