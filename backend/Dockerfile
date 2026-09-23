FROM python:3.14-slim

WORKDIR /srv
COPY backend /srv/backend
COPY contracts /srv/contracts
WORKDIR /srv/backend
RUN pip install --no-cache-dir .
ENV CONTRACTS_PATH=/srv/contracts/default_experiment.json
ENV RAW_DATA_DIR=/data/raw
CMD ["sh", "-c", "python -m app.wait_for_db && alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000"]
