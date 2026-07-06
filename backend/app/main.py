from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="ZZCare Sleep Snore API",
    description="수면/코골이 분석 앱 백엔드",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def root():
    return {
        "message": "ZZCare backend is running",
        "docs": "/docs"
    }

@app.get("/health")
def health_check():
    return {
        "status": "ok"
    }