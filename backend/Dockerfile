FROM node:22-slim AS editor
WORKDIR /web
COPY web/package*.json ./
RUN npm ci --no-audit --no-fund
COPY web ./
RUN npm run build

FROM python:3.14-slim

RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*

WORKDIR /srv
COPY backend /srv/backend
COPY contracts /srv/contracts
COPY --from=editor /web/dist /srv/web/dist
WORKDIR /srv/backend
RUN pip install --no-cache-dir .
ENV CONTRACTS_PATH=/srv/contracts/default_experiment.json
ENV EDITOR_DIST_DIR=/srv/web/dist
ENV AUDIO_DATA_DIR=/data/audio
ENV RAW_DATA_DIR=/data/raw
CMD ["sh", "-c", "python -m app.wait_for_db && alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000"]
