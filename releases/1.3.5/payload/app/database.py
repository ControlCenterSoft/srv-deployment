from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker


DATABASE_URL = (
    "postgresql+psycopg://srv-control@/srv_control"
    "?host=/var/run/postgresql"
)


engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    future=True,
)


SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
    future=True,
)


Base = declarative_base()


def get_db():
    db = SessionLocal()

    try:
        yield db

    finally:
        db.close()
