from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from prometheus_fastapi_instrumentator import Instrumentator

from app.backend.db import init_db, engine
from app.routers import upload


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    await init_db()
    yield
    # Shutdown
    await engine.dispose()


app = FastAPI(title="UploadDocsService", lifespan=lifespan)

instrumentator = Instrumentator()
instrumentator.instrument(app).expose(app)

origins = [
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "http://localhost:5173",
    "http://127.0.0.1:5173",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(upload.router, prefix="/api")

from fastapi import Response
import json


@app.get("/health", response_class=Response)
async def health_check():
    try:
        data = {"status": "healthy", "timestamp": datetime.now(timezone.utc).isoformat()}
        return Response(
            content=json.dumps(data),
            media_type="text/plain"
        )
    except Exception as e:
        return Response(
            content=json.dumps({"status": "unhealthy", "error": str(e)}),
            media_type="text/plain",
            status_code=500
        )
