import os

from dotenv import load_dotenv
from pymongo import MongoClient

load_dotenv()

MONGO_URL = os.getenv("MONGO_URL", "mongodb://localhost:27017")
DB_NAME = os.getenv("DB_NAME", "zzcare")

client = MongoClient(MONGO_URL)
db = client[DB_NAME]

users_collection = db["users"]

users_collection.create_index(
    [("provider", 1), ("kakao_id", 1)],
    unique=True,
)