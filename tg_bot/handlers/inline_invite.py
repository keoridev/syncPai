import html
import logging
import random
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

from aiogram import F, Router
from aiogram.types import (
    CallbackQuery,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    InlineQuery,
    InlineQueryResultArticle,
    InputTextMessageContent,
)

from db import supabase_client
from db.supabase_client import supabase

logger = logging.getLogger(__name__)
router = Router(name="inline_invite")


def _extract_clean_room_code(raw: str) -> str:
    clean = raw.strip().upper()
    if clean.startswith("SP-"):
        clean = clean[3:]
    return clean


def _find_active_room(query: str, tg_id: int) -> Optional[Dict[str, Any]]:
    cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
    try:
        clean = _extract_clean_room_code(query)
        row: Optional[Dict[str, Any]] = None

        if clean:
            res = (
                supabase.table("rooms")
                .select("*")
                .eq("id", clean)
                .limit(1)
                .execute()
            )
            if res.data:
                row = res.data[0]
        else:
            profile = supabase_client.get_profile_by_tg_id(tg_id)
            if profile:
                res = (
                    supabase.table("rooms")
                    .select("*")
                    .eq("host_id", profile["id"])
                    .order("updated_at", desc=True)
                    .limit(1)
                    .execute()
                )
                if res.data:
                    row = res.data[0]

        if not row:
            return None

        updated_raw = str(row.get("updated_at") or row.get("created_at") or "")
        if updated_raw:
            try:
                dt = datetime.fromisoformat(updated_raw.replace("Z", "+00:00"))
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=timezone.utc)
                if dt < cutoff:
                    return None
            except ValueError:
                pass
        return row
    except Exception as e:
        logger.warning(f"[InlineInvite] Room lookup error: {e}")
        return None


@router.inline_query()
async def handle_inline_room_invite(inline_query: InlineQuery):
    room = _find_active_room(inline_query.query or "", inline_query.from_user.id)
    if not room:
        await inline_query.answer(results=[], cache_time=5, is_personal=True)
        return

    room_code = str(room.get("id") or "")
    anime_title = html.escape(str(room.get("anime_title") or "Аниме в SyncPai"))
    raw_title = str(room.get("anime_title") or "Аниме в SyncPai")
    ep_num = int(room.get("episode_index") or 0) + 1
    poster_url = str(room.get("poster_url") or "")

    message_html = (
        f"🍿 <b>Го смотреть вместе в SyncPai!</b>\n\n"
        f"Аниме: <b>{anime_title}</b>\n"
        f"Серия: <b>{ep_num}</b>\n"
        f"Код комнаты: <code>{html.escape(room_code)}</code>"
    )

    article = InlineQueryResultArticle(
        id=f"room_{room_code}",
        title=f"🎬 Приглашение в SyncPai: {raw_title}",
        description=f"Серия {ep_num} • Код комнаты: {room_code} • Нажмите, чтобы отправить приглашение",
        thumbnail_url=poster_url if poster_url.startswith("http") else None,
        input_message_content=InputTextMessageContent(
            message_text=message_html,
            parse_mode="HTML",
        ),
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[
            [
                InlineKeyboardButton(
                    text=f"🚀 Войти в комнату ({room_code})",
                    url=f"https://syncpai.app/room/{room_code}",
                )
            ]
        ]),
    )

    await inline_query.answer(
        results=[article],
        cache_time=5,
        is_personal=True,
    )


@router.callback_query(F.data.startswith("quick_room:"))
async def cb_quick_room(callback: CallbackQuery):
    parts = (callback.data or "").split(":")
    if len(parts) < 3:
        await callback.answer("Некорректные данные", show_alert=True)
        return

    release_id = parts[1]
    ep_num = int(parts[2]) if parts[2].isdigit() else 1
    profile = supabase_client.get_profile_by_tg_id(callback.from_user.id)
    if not profile:
        await callback.answer("Сначала привяжите аккаунт SyncPai", show_alert=True)
        return

    pin = str(random.randint(100000, 999999))
    try:
        supabase.table("rooms").insert({
            "id": pin,
            "host_id": profile["id"],
            "anime_id": str(release_id),
            "anime_title": f"Релиз #{release_id}",
            "episode_index": max(0, ep_num - 1),
            "is_playing": False,
            "current_time_sec": 0.0,
        }).execute()
    except Exception as e:
        logger.warning(f"[InlineInvite] quick_room insert error: {e}")
        await callback.answer("Не удалось создать комнату", show_alert=True)
        return

    await callback.answer()
    if callback.message:
        await callback.message.answer(
            f"🍿 <b>Комната создана!</b>\n\n"
            f"Серия: <b>{ep_num}</b>\n"
            f"Код комнаты: <code>{pin}</code>",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [
                    InlineKeyboardButton(
                        text=f"🚀 Войти в комнату ({pin})",
                        url=f"https://syncpai.app/room/{pin}",
                    )
                ]
            ]),
        )

