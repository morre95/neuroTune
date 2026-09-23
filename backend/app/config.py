from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./neurotune.db"
    jwt_secret: str = "dev-only-change-me"
    raw_data_dir: str = "./raw"
    contracts_path: str = "../contracts/default_experiment.json"
    access_token_minutes: int = 15
    refresh_token_days: int = 30


settings = Settings()
