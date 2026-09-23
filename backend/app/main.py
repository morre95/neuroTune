import json
import uuid
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI

from app.config import settings
from app.db import Base, SessionLocal, engine
from app.models import Experiment
from app.routers import auth, bandit, experiments, sessions, training


def seed_experiment() -> None:
    path = Path(settings.contracts_path)
    if not path.exists():
        return
    body = json.loads(path.read_text())
    db = SessionLocal()
    try:
        existing = db.query(Experiment).filter(Experiment.version == body["version"]).one_or_none()
        if existing is None:
            db.add(Experiment(id=str(uuid.uuid4()), version=body["version"], body=json.dumps(body), active=True))
            db.commit()
    finally:
        db.close()


@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(engine)
    seed_experiment()
    yield


app = FastAPI(title="neuroTune", version="0.1.0", lifespan=lifespan)
app.include_router(auth.router, prefix="/v1")
app.include_router(experiments.router, prefix="/v1")
app.include_router(sessions.router, prefix="/v1")
app.include_router(training.router, prefix="/v1")
app.include_router(bandit.router, prefix="/v1")


@app.get("/v1/health")
def health() -> dict:
    return {"ok": True}
