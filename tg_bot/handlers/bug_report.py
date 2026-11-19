import html
import logging
from typing import Optional

from aiogram import F, Router
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import (
    CallbackQuery,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    Message,
)

from config import settings
from db import supabase_client
from db.supabase_client import supabase

logger = logging.getLogger(__name__)
router = Router(name="bug_report")


class BugReportStates(StatesGroup):
    waiting_for_report = State()


async def start_bug_report_flow(
    message: Message,
    state: FSMContext,
    friend_token: Optional[str] = None,
):
    profile = None
    if friend_token:
        profile = supabase_client.get_profile_by_code_or_tag(friend_token)
    if not profile:
        profile = supabase_client.get_profile_by_tg_id(message.from_user.id)

    await state.set_state(BugReportStates.waiting_for_report)
    await state.update_data(
        target_user_id=profile["id"] if profile else "",
        target_username=(
            f"{profile.get('username')}{profile.get('tag') or ''}"
            if profile
            else (message.from_user.username or "Гость")
        ),
        friend_code=profile.get("friend_code") if profile else (friend_token or ""),
    )

    unlinked_hint = ""
    if not profile:
        unlinked_hint = (
            "\n\n<i>Совет: твой Telegram ещё не привязан к SyncPai — можешь указать "
            "код дружбы (<code>SP-XXXXXX</code>) прямо в тексте или привязать аккаунт в приложении, "
            "чтобы мы знали, на какой профиль выдать значок.</i>"
        )

    await message.answer(
        "🐞 <b>Нашли баг в SyncPai?</b>\n\n"
        "Опишите проблему одним сообщением (можно прикрепить скриншот). "
        "Если баг подтвердится, вы получите эксклюзивный значок <b>«Кодинг-хакер»</b> в профиле!"
        f"{unlinked_hint}",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="← Отмена", callback_data="cancel_action")],
        ]),
    )


@router.callback_query(F.data == "report_bug")
async def cb_report_bug(callback: CallbackQuery, state: FSMContext):
    await callback.answer()
    if callback.message:
        await start_bug_report_flow(callback.message, state)


@router.message(BugReportStates.waiting_for_report)
async def process_bug_description(message: Message, state: FSMContext):
    data = await state.get_data()
    user_id = str(data.get("target_user_id") or "")
    username = str(data.get("target_username") or message.from_user.username or "Пользователь")
    friend_code = str(data.get("friend_code") or "")
    tg_id = message.from_user.id
    description = (message.text or message.caption or "").strip()
    photo_id = message.photo[-1].file_id if message.photo else None

    if not description and not photo_id:
        await message.answer("Пожалуйста, опишите проблему текстом или приложите скриншот с подписью.")
        return

    report_id = "local"
    try:
        res = (
            supabase.table("bug_reports")
            .insert({
                "user_id": user_id or None,
                "telegram_id": tg_id,
                "username": username,
                "description": description or "[Скриншот без текста]",
                "status": "pending",
            })
            .execute()
        )
        if res.data and isinstance(res.data, list):
            report_id = str(res.data[0].get("id") or "local")
    except Exception as e:
        logger.warning(f"[BugReport] Insert failed: {e}")

    await state.clear()
    await message.answer(
        "✅ <b>Репорт отправлен команде SyncPai!</b>\n\n"
        "Как только администратор подтвердит баг, вы получите уведомление и значок <b>«Кодинг-хакер»</b>.",
        parse_mode="HTML",
    )

    admin_text = (
        f"🐞 <b>Новый баг-репорт #{html.escape(report_id)}</b>\n\n"
        f"• <b>Пользователь:</b> {html.escape(username)} (TG ID: <code>{tg_id}</code>)\n"
        f"• <b>Код дружбы:</b> <code>{html.escape(friend_code or '—')}</code>\n"
        f"• <b>Profile ID:</b> <code>{html.escape(user_id or 'не привязан')}</code>\n"
        f"• <b>Описание:</b>\n{html.escape(description or 'Без текста')}"
    )
    admin_kb = InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(
                text="✅ Одобрить и выдать «Кодинг-хакер»",
                callback_data=f"bug_approve:{report_id}:{user_id}:{tg_id}",
            )
        ],
        [
            InlineKeyboardButton(
                text="❌ Отклонить",
                callback_data=f"bug_reject:{report_id}",
            )
        ],
    ])

    try:
        if photo_id:
            await message.bot.send_photo(
                chat_id=settings.admin_telegram_id,
                photo=photo_id,
                caption=admin_text,
                parse_mode="HTML",
                reply_markup=admin_kb,
            )
        else:
            await message.bot.send_message(
                chat_id=settings.admin_telegram_id,
                text=admin_text,
                parse_mode="HTML",
                reply_markup=admin_kb,
            )
    except Exception as e:
        logger.warning(f"[BugReport] Admin forward error: {e}")


@router.callback_query(F.data.startswith("bug_approve:"))
async def cb_approve_bug(callback: CallbackQuery):
    if callback.from_user.id != settings.admin_telegram_id:
        await callback.answer("Недостаточно прав", show_alert=True)
        return

    parts = (callback.data or "").split(":")
    report_id = parts[1] if len(parts) > 1 else ""
    profile_id = parts[2] if len(parts) > 2 else ""
    tg_id = int(parts[3]) if len(parts) > 3 and parts[3].isdigit() else 0

    if profile_id:
        granted = False
        try:
            supabase.rpc(
                "grant_profile_badge",
                {"target_user_id": profile_id, "badge_id": "bug_hunter"},
            ).execute()
            granted = True
        except Exception as e:
            logger.debug(f"[BugReport] RPC fallback: {e}")

        if not granted:
            try:
                row = (
                    supabase.table("profiles")
                    .select("unlocked_badges")
                    .eq("id", profile_id)
                    .limit(1)
                    .execute()
                )
                existing = []
                if row.data:
                    existing = list(row.data[0].get("unlocked_badges") or [])
                if "bug_hunter" not in existing:
                    existing.append("bug_hunter")
                    supabase.table("profiles").update(
                        {"unlocked_badges": existing}
                    ).eq("id", profile_id).execute()
            except Exception as e:
                logger.warning(f"[BugReport] Fallback badge update error: {e}")

    if report_id and report_id != "local":
        try:
            supabase.table("bug_reports").update(
                {"status": "verified"}
            ).eq("id", report_id).execute()
        except Exception:
            pass

    await callback.answer("Значок выдан!")
    if callback.message:
        try:
            if callback.message.caption is not None:
                await callback.message.edit_caption(
                    caption=f"{callback.message.caption}\n\n✅ <b>Одобрено — значок «Кодинг-хакер» выдан!</b>",
                    parse_mode="HTML",
                    reply_markup=None,
                )
            else:
                await callback.message.edit_text(
                    text=f"{callback.message.text}\n\n✅ <b>Одобрено — значок «Кодинг-хакер» выдан!</b>",
                    parse_mode="HTML",
                    reply_markup=None,
                )
        except Exception:
            await callback.message.edit_reply_markup(reply_markup=None)

    if tg_id > 0:
        try:
            await callback.bot.send_message(
                chat_id=tg_id,
                text=(
                    "👾 <b>Баг подтверждён!</b> Спасибо за помощь в улучшении SyncPai — "
                    "вам выдан редкий значок <b>«Кодинг-хакер»</b>!"
                ),
                parse_mode="HTML",
            )
        except Exception:
            pass


@router.callback_query(F.data.startswith("bug_reject:"))
async def cb_reject_bug(callback: CallbackQuery):
    if callback.from_user.id != settings.admin_telegram_id:
        await callback.answer("Недостаточно прав", show_alert=True)
        return

    parts = (callback.data or "").split(":")
    report_id = parts[1] if len(parts) > 1 else ""
    if report_id and report_id != "local":
        try:
            supabase.table("bug_reports").update(
                {"status": "rejected"}
            ).eq("id", report_id).execute()
        except Exception:
            pass

    await callback.answer("Отклонено")
    if callback.message:
        await callback.message.edit_reply_markup(reply_markup=None)
        await callback.message.reply("❌ Баг-репорт отклонён.")
