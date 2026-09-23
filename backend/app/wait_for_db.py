import time

from sqlalchemy import create_engine, text

from app.config import settings


def main() -> None:
    for _ in range(30):
        try:
            engine = create_engine(settings.database_url)
            with engine.connect() as connection:
                connection.execute(text("SELECT 1"))
            return
        except Exception:
            time.sleep(1)
    raise SystemExit("database did not become ready")


if __name__ == "__main__":
    main()
