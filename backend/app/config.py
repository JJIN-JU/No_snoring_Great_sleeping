from pathlib import Path

# ==========================================
# Project Path
# ==========================================

BASE_DIR = Path(__file__).resolve().parent.parent
MODEL_DIR = BASE_DIR / "models"
UPLOAD_DIR = BASE_DIR / "uploads"

# ==========================================
# Model Files
# ==========================================

BINARY_MODEL_NAME = "librosa_binary_baseline.keras"
MULTILABEL_MODEL_NAME = "librosa_binary_adam_multi.keras"

# ==========================================
# Audio
# ==========================================

SEGMENT_SECONDS = 1
WINDOW_SECONDS = 5
SAMPLE_RATE = None

# ==========================================
# MFCC
# ==========================================

MFCC_SIZE = 32
N_FFT = 512

# ==========================================
# Threshold
# ==========================================

BINARY_THRESHOLD = 0.50
SEGMENT_THRESHOLD = 0.50
VOTE_THRESHOLD = 3

MULTI_THRESHOLDS = {
    "Snoring": 0.50,
    "Baby": 0.32,
    "Door": 0.16,
    "Environmental": 0.50,
    "Etc": 0.50,
    "Toilet": 0.50,
    "VoiceTV": 0.88,
    "Vehicles": 0.50,
    "Vibration": 0.50,
    "WhiteNoise": 0.53,
}

# ==========================================
# Labels
# ==========================================

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

# ==========================================
# Realtime
# ==========================================

SNORE_ALERT_COOLDOWN_SECONDS = 30