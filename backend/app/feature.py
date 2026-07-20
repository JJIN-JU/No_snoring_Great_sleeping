import os
import numpy as np
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt
import inspect


import warnings
warnings.filterwarnings("ignore")

import scipy.io.wavfile as wav
import librosa
from tqdm import tqdm
import IPython.display as ipd

import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers
from keras.models import Sequential
from sklearn.preprocessing import LabelEncoder
from sklearn.model_selection import train_test_split

from app.config import MFCC_SIZE, N_FFT

def extract_librosa_binary_mfcc(filepath):

    signal, sr = librosa.load(
        filepath,
        sr=44100,
        mono=True
    )

    mfcc = librosa.feature.mfcc(
        y=signal,
        sr=sr,
        n_mfcc=MFCC_SIZE,
        n_fft=N_FFT,
    )

    # 길이 맞추기
    if mfcc.shape[1] < MFCC_SIZE:
        pad = MFCC_SIZE - mfcc.shape[1]
        mfcc = np.pad(mfcc, ((0, 0), (0, pad)), mode="constant")
    else:
        mfcc = mfcc[:, :MFCC_SIZE]

    return mfcc