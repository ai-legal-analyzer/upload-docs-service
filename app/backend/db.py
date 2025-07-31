import os
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.orm import DeclarativeBase

DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql+asyncpg://postgres:postgres@db:5432/postgres')

engine = create_async_engine(DATABASE_URL)
async_session_maker = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


class Base(DeclarativeBase):
    pass


async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


def get_async_session() -> AsyncSession:
    """Get an async session for use in Celery tasks."""
    return async_session_maker()


async def get_db_session() -> AsyncSession:
    """Get an async session for use in FastAPI endpoints."""
    async with async_session_maker() as session:
        return session

