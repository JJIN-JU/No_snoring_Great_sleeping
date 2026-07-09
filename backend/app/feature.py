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
import os

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