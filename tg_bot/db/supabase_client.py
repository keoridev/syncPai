import logging
from typing import Optional, Dict, Any, List
from supabase import create_client, Client
from config import settings

logger = logging.getLogger(__name__)

# Official Supabase client initialized with SERVICE_ROLE_KEY for admin privilege
supabase: Client = create_client(
    supabase_url=settings.supabase_url,
    supabase_key=settings.supabase_service_role_key,
)


def get_profile_by_tg_id(tg_id: int) -> Optional[Dict[str, Any]]:
    """Поиск профиля SyncPai по привязанному telegram_id."""
    try:
        res = (
            supabase.table("profiles")
            .select("*")
            .eq("telegram_id", tg_id)
            .limit(1)
            .execute()
        )
        if res.data and len(res.data) > 0:
            return res.data[0]
        return None
    except Exception as e:
        logger.error(f"Error fetching profile by telegram_id {tg_id}: {e}")
        return None


def get_profile_by_code_or_tag(identifier: str) -> Optional[Dict[str, Any]]:
    """Поиск профиля по SP-XXXXXX (friend_code), username#tag или id (UUID)."""
    clean = identifier.strip()
    try:
        # 1. По friend_code (например, SP-ABC123)
        if clean.upper().startswith("SP-"):
            res = (
                supabase.table("profiles")
                .select("*")
                .ilike("friend_code", clean)
                .limit(1)
                .execute()
            )
            if res.data and len(res.data) > 0:
                return res.data[0]

        # 2. По username#tag (например, KenKaneki#1337)
        if "#" in clean:
            parts = clean.split("#", 1)
            uname = parts[0].strip()
            tag = f"#{parts[1].strip()}"
            res = (
                supabase.table("profiles")
                .select("*")
                .ilike("username", uname)
                .eq("tag", tag)
                .limit(1)
                .execute()
            )
            if res.data and len(res.data) > 0:
                return res.data[0]

        # 3. По UUID id
        if len(clean) >= 32:
            res = (
                supabase.table("profiles")
                .select("*")
                .eq("id", clean)
                .limit(1)
                .execute()
            )
            if res.data and len(res.data) > 0:
                return res.data[0]

        # 4. По username
        res = (
            supabase.table("profiles")
            .select("*")
            .ilike("username", clean)
            .limit(1)
            .execute()
        )
        if res.data and len(res.data) > 0:
            return res.data[0]

        return None
    except Exception as e:
        logger.error(f"Error finding profile by {identifier}: {e}")
        return None


def link_profile_telegram(profile_id: str, tg_id: int, tg_username: Optional[str] = None) -> bool:
    """Привязка Telegram ID к аккаунту SyncPai."""
    try:
        supabase.table("profiles").update({
            "telegram_id": tg_id,
            "telegram_username": tg_username or "",
        }).eq("id", profile_id).execute()
        return True
    except Exception as e:
        logger.error(f"Error linking telegram {tg_id} to {profile_id}: {e}")
        return False


def unlink_profile_telegram(profile_id: str) -> bool:
    """Отвязка Telegram ID."""
    try:
        supabase.table("profiles").update({
            "telegram_id": None,
            "telegram_username": None,
        }).eq("id", profile_id).execute()
        return True
    except Exception as e:
        logger.error(f"Error unlinking telegram for {profile_id}: {e}")
        return False


def set_supporter_tier(profile_id: str, tier_id: str, days: int = 30) -> bool:
    """Активация уровня поддержки в профиле пользователя."""
    try:
        from datetime import datetime, timezone, timedelta
        expires_at = datetime.now(timezone.utc) + timedelta(days=days)

        payload = {
            "supporter_tier": tier_id,
            "supporter_until": expires_at.isoformat(),
        }
        supabase.table("profiles").update(payload).eq("id", profile_id).execute()
        return True
    except Exception as e:
        logger.error(f"Error setting supporter tier {tier_id} for {profile_id}: {e}")
        return False


def get_latest_app_config() -> Optional[Dict[str, Any]]:
    """Получение конфигурации приложения и ссылок на сборки из public.app_config."""
    try:
        res = (
            supabase.table("app_config")
            .select("*")
            .order("id", desc=True)
            .limit(1)
            .execute()
        )
        if res.data and len(res.data) > 0:
            return res.data[0]
        return None
    except Exception as e:
        logger.error(f"Error fetching app_config: {e}")
        return None


def get_expired_supporters() -> List[Dict[str, Any]]:
    """Поиск пользователей, у которых истёк срок действия supporter_tier."""
    try:
        from datetime import datetime, timezone
        now_iso = datetime.now(timezone.utc).isoformat()
        res = (
            supabase.table("profiles")
            .select("id, username, supporter_tier, supporter_until, telegram_id")
            .neq("supporter_tier", "free")
            .lt("supporter_until", now_iso)
            .execute()
        )
        return res.data or []
    except Exception as e:
        logger.error(f"Error querying expired supporters: {e}")
        return []


def downgrade_to_free(profile_id: str) -> bool:
    """Сброс supporter_tier на 'free'."""
    try:
        supabase.table("profiles").update({
            "supporter_tier": "free",
            "supporter_until": None,
        }).eq("id", profile_id).execute()
        return True
    except Exception as e:
        logger.error(f"Error downgrading {profile_id} to free: {e}")
        return False

