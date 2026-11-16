import logging
import re
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional
from supabase import Client, create_client
from config import settings

logger = logging.getLogger(__name__)

_UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)

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
        if res.data:
            return res.data[0]
        return None
    except Exception as e:
        logger.error(f"Error fetching profile by telegram_id {tg_id}: {e}")
        return None


def get_profile_by_code_or_tag(identifier: str) -> Optional[Dict[str, Any]]:
    """Поиск профиля по SP-XXXXXX (friend_code), username#tag или UUID."""
    clean = identifier.strip()
    if not clean:
        return None
    try:
        # 1. По friend_code (например, SP-ABC123 или SPABC123)
        upper = clean.upper()
        if upper.startswith("SP-") or (upper.startswith("SP") and len(upper) >= 6):
            code = upper if upper.startswith("SP-") else f"SP-{upper[2:]}"
            res = (
                supabase.table("profiles")
                .select("*")
                .ilike("friend_code", code)
                .limit(1)
                .execute()
            )
            if res.data:
                return res.data[0]

        # 2. По username#tag (поддержка tag как '#1337', так и '1337')
        if "#" in clean:
            parts = clean.split("#", 1)
            uname = parts[0].strip()
            clean_tag = parts[1].strip().lstrip("#")
            if uname and clean_tag:
                res = (
                    supabase.table("profiles")
                    .select("*")
                    .ilike("username", uname)
                    .in_("tag", [clean_tag, f"#{clean_tag}"])
                    .limit(1)
                    .execute()
                )
                if res.data:
                    return res.data[0]

        # 3. По строгому UUID id
        if _UUID_RE.match(clean):
            res = (
                supabase.table("profiles")
                .select("*")
                .eq("id", clean)
                .limit(1)
                .execute()
            )
            if res.data:
                return res.data[0]

        # 4. По username
        res = (
            supabase.table("profiles")
            .select("*")
            .ilike("username", clean)
            .limit(1)
            .execute()
        )
        if res.data:
            return res.data[0]

        return None
    except Exception as e:
        logger.error(f"Error finding profile by {identifier}: {e}")
        return None


def link_profile_telegram(profile_id: str, tg_id: int, tg_username: Optional[str] = None) -> bool:
    """Привязка Telegram ID к аккаунту SyncPai."""
    try:
        res = (
            supabase.table("profiles")
            .update({
                "telegram_id": tg_id,
                "telegram_username": tg_username or "",
            })
            .eq("id", profile_id)
            .execute()
        )
        return bool(res.data)
    except Exception as e:
        logger.error(f"Error linking telegram {tg_id} to {profile_id}: {e}")
        return False


def unlink_profile_telegram(profile_id: str) -> bool:
    """Отвязка Telegram ID."""
    try:
        res = (
            supabase.table("profiles")
            .update({
                "telegram_id": None,
                "telegram_username": None,
            })
            .eq("id", profile_id)
            .execute()
        )
        return bool(res.data)
    except Exception as e:
        logger.error(f"Error unlinking telegram for {profile_id}: {e}")
        return False


def set_supporter_tier(profile_id: str, tier_id: str, days: int = 30) -> bool:
    """Активация уровня поддержки в профиле пользователя."""
    try:
        expires_at = datetime.now(timezone.utc) + timedelta(days=days)
        payload = {
            "supporter_tier": tier_id,
            "supporter_until": expires_at.isoformat(),
        }
        res = supabase.table("profiles").update(payload).eq("id", profile_id).execute()
        return bool(res.data)
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
        if res.data:
            return res.data[0]
        return None
    except Exception as e:
        logger.error(f"Error fetching app_config: {e}")
        return None


def get_expired_supporters() -> List[Dict[str, Any]]:
    """Поиск пользователей, у которых истёк срок действия supporter_tier."""
    try:
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
        res = (
            supabase.table("profiles")
            .update({
                "supporter_tier": "free",
                "supporter_until": None,
            })
            .eq("id", profile_id)
            .execute()
        )
        return bool(res.data)
    except Exception as e:
        logger.error(f"Error downgrading {profile_id} to free: {e}")
        return False
