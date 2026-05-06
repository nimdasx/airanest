from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "AiraNest API"
    debug: bool = False

    database_url: str = "postgresql://airanest:airanest@postgres:5432/airanest"
    redis_url: str = "redis://redis:6379/0"

    secret_key: str = "change-me-in-production"
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 7

    encryption_key: str = "change-me-in-production"

    storage_path: str = "/app/storage"

    class Config:
        env_file = ".env"


settings = Settings()
