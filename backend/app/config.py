from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# HS256 signs with the raw secret, so a key shorter than the SHA-256 output
# weakens the signature. RFC 7518 section 3.2 requires at least 32 bytes.
MIN_JWT_SECRET_BYTES = 32

# Dev-only placeholder. Long enough to sign with, refused outside development.
DEV_JWT_SECRET = "dev-only-insecure-secret-change-me"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    environment: str = "development"
    database_url: str = "sqlite:///./neurotune.db"
    jwt_secret: str = DEV_JWT_SECRET
    raw_data_dir: str = "./raw"
    contracts_path: str = "../contracts/default_experiment.json"
    access_token_minutes: int = 15
    refresh_token_days: int = 30

    @model_validator(mode="after")
    def check_jwt_secret(self) -> "Settings":
        if len(self.jwt_secret.encode()) < MIN_JWT_SECRET_BYTES:
            raise ValueError(
                f"JWT_SECRET must be at least {MIN_JWT_SECRET_BYTES} bytes. "
                "Generate one with: python -c 'import secrets; print(secrets.token_urlsafe(32))'"
            )
        if self.environment != "development" and self.jwt_secret == DEV_JWT_SECRET:
            raise ValueError(
                f"JWT_SECRET is still the development default in environment "
                f"'{self.environment}'. Set a real secret."
            )
        return self


settings = Settings()
