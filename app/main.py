from contextlib import asynccontextmanager
from fastapi import FastAPI
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

app.include_router(upload.router, prefix="/api")
