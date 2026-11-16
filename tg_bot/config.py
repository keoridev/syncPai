from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional


class Settings(BaseSettings):
    bot_token: str
    supabase_url: str
    supabase_service_role_key: str
    admin_telegram_id: int
    support_chat_id: Optional[int] = None

    # Payment details / links
    boosty_url: str = "https://boosty.to/syncpai"
    crypto_usdt_trc20: str = "TXxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    crypto_ton: str = "EQxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    tribute_url: str = "https://t.me/tribute/app?startapp=syncpai"
    payment_provider_token: str = ""

    log_level: str = "INFO"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )


settings = Settings()

