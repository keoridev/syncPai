import html
import logging
from typing import Any, Dict, List

import aiohttp
from aiogram import Bot
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

from db.supabase_client import supabase

logger = logging.getLogger(__name__)

ANILIBRIA_LATEST_URL = "https://anilibria.top/api/v1/anime/releases/latest?limit=15"


async def fetch_latest_releases() -> List[Dict[str, Any]]:
    """Получить свежие релизы с AniLibria API v1."""
    timeout = aiohttp.ClientTimeout(total=10)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        async with session.get(ANILIBRIA_LATEST_URL) as resp:
            if resp.status != 200:
                return []
            data = await resp.json()
            if isinstance(data, list):
                return [x for x in data if isinstance(x, dict)]
            if isinstance(data, dict) and isinstance(data.get("data"), list):
                return [x for x in data["data"] if isinstance(x, dict)]
            return []


async def check_and_notify_new_episodes(bot: Bot) -> int:
    """Фоновый воркер: проверяет новые серии AniLibria и рассылает алерты подписчикам."""
    sent_count = 0
    try:
        releases = await fetch_latest_releases()
    except Exception as e:
        logger.warning(f"[EpisodeNotifier] AniLibria fetch error: {e}")
        return 0

    for rel in releases:
        release_id = rel.get("id")
        latest_ep = rel.get("latest_episode") or {}
        ep_num = latest_ep.get("ordinal")
        if not release_id or not ep_num:
            continue

        try:
            existing = (
                supabase.table("notified_episodes")
                .select("id")
                .eq("release_id", int(release_id))
                .eq("episode_number", int(ep_num))
                .limit(1)
                .execute()
            )
            if existing.data:
                continue

            supabase.table("notified_episodes").insert({
                "release_id": int(release_id),
                "episode_number": int(ep_num),
            }).execute()
        except Exception as e:
            logger.debug(f"[EpisodeNotifier] notified_episodes check/insert skipped: {e}")
            continue

        name_obj = rel.get("name") or {}
        raw_title = (
            name_obj.get("main")
            or name_obj.get("russian")
            or name_obj.get("english")
            or f"Аниме #{release_id}"
        )
        safe_title = html.escape(str(raw_title))

        # Находим пользователей, у которых тайтл в статусе 'watching' и привязан Telegram
        try:
            watching_rows = (
                supabase.table("user_anime_lists")
                .select("user_id")
                .eq("anime_id", int(release_id))
                .eq("status", "watching")
                .execute()
            )
            user_ids = list({
                str(r["user_id"])
                for r in (watching_rows.data or [])
                if r.get("user_id")
            })
            if not user_ids:
                continue

            profiles_res = (
                supabase.table("profiles")
                .select("id, telegram_id")
                .in_("id", user_ids)
                .not_.is_("telegram_id", "null")
                .execute()
            )
            tg_ids = [
                int(p["telegram_id"])
                for p in (profiles_res.data or [])
                if p.get("telegram_id")
            ]
        except Exception as e:
            logger.warning(f"[EpisodeNotifier] Supabase recipients error: {e}")
            continue

        keyboard = InlineKeyboardMarkup(inline_keyboard=[
            [
                InlineKeyboardButton(
                    text=f"▶️ Смотреть {ep_num} серию",
                    url=f"https://syncpai.app/open?anime={release_id}&ep={ep_num}",
                )
            ],
            [
                InlineKeyboardButton(
                    text="👥 Создать комнату Вместе",
                    callback_data=f"quick_room:{release_id}:{ep_num}",
                )
            ],
        ])

        text = (
            f"🎬 <b>Вышла новая серия!</b>\n\n"
            f"<b>{safe_title}</b> — <b>Серия {ep_num}</b> уже доступна в озвучке AniLibria."
        )

        for tg_id in tg_ids:
            try:
                await bot.send_message(
                    chat_id=tg_id,
                    text=text,
                    parse_mode="HTML",
                    reply_markup=keyboard,
                )
                sent_count += 1
            except Exception as e:
                logger.debug(f"[EpisodeNotifier] Failed to notify {tg_id}: {e}")

    return sent_count

