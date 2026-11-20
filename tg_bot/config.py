from pathlib import Path
from typing import Optional
from pydantic_settings import BaseSettings, SettingsConfigDict

_ENV_PATH = Path(__file__).resolve().parent / ".env"


class Settings(BaseSettings):
    bot_token: str
    supabase_url: str
    supabase_service_role_key: str
    admin_telegram_id: Optional[int] = None
    admin_ids: str = ""
    support_chat_id: Optional[int] = None

    # Server infrastructure goal
    monthly_goal_current: int = 1450
    monthly_goal_target: int = 3000
    monthly_goal_title: str = "Оплата VDS и инфраструктуры на месяц"

    # Anonymous privacy-preserving payment methods (zero bank cards / zero personal names)
    # Shown only if explicitly configured in .env:
    pay_crypto_bot_link: Optional[str] = None  # PAY_CRYPTO_BOT_LINK: @CryptoBot link under brand "SyncPai"
    pay_ton: Optional[str] = None  # PAY_TON: Anonymous TON wallet address
    pay_tribute: Optional[str] = None  # PAY_TRIBUTE: @tribute link under brand "SyncPai"
    payment_provider_token: str = ""

    log_level: str = "INFO"

    model_config = SettingsConfigDict(
        env_file=str(_ENV_PATH),
        env_file_encoding="utf-8",
        extra="ignore",
    )


settings = Settings()
