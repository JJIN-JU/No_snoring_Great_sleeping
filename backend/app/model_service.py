from tensorflow.keras.models import load_model

binary_model = load_model("models/binary.keras")
multilabel_model = load_model("models/multilabel.keras")
