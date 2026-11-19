import asyncio
import html
import logging
from typing import Optional

from aiogram import F, Router
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import (
    CallbackQuery,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    InputMediaDocument,
    InputMediaPhoto,
    InputMediaVideo,
    Message,
)

from config import settings
from db import supabase_client
from db.supabase_client import supabase

logger = logging.getLogger(__name__)
router = Router(name="bug_report")
_user_draft_locks: dict[int, asyncio.Lock] = {}


def _get_user_lock(tg_id: int) -> asyncio.Lock:
    lock = _user_draft_locks.get(tg_id)
    if lock is None:
        lock = asyncio.Lock()
        _user_draft_locks[tg_id] = lock
    return lock


class BugReportStates(StatesGroup):
    waiting_for_report = State()


class AdminReplyStates(StatesGroup):
    waiting_for_reply_text = State()


def _resolve_admin_tg_ids() -> list[int]:
    ids: list[int] = []
    if settings.admin_ids:
        for raw in settings.admin_ids.split(","):
            raw = raw.strip()
            if raw.isdigit():
                val = int(raw)
                if val > 0 and val not in ids:
                    ids.append(val)
    if settings.admin_telegram_id and settings.admin_telegram_id > 0:
        if settings.admin_telegram_id not in ids:
            ids.append(settings.admin_telegram_id)

    if not ids:
        try:
            res = (
                supabase.table("profiles")
                .select("telegram_id, username, supporter_tier")
                .not_.is_("telegram_id", "null")
                .or_("username.ilike.keoribek%,supporter_tier.eq.founders")
                .limit(5)
                .execute()
            )
            for row in (res.data or []):
                tg_val = row.get("telegram_id")
                if tg_val is not None:
                    val = int(tg_val)
                    if val > 0 and val not in ids:
                        ids.append(val)
        except Exception as e:
            logger.warning(f"[BugReport] Admin fallback lookup failed: {e}")
    if not ids:
        ids.append(1110337748)
    return ids


def _build_draft_text(texts: list[str], media: list[tuple[str, str]]) -> str:
    has_text_status = "Добавлен ✅" if texts else "Пока нет"
    return (
        "🐞 <b>Черновик баг-репорта:</b>\n"
        f"• Текст: <b>{has_text_status}</b>\n"
        f"• Вложений: <b>{len(media)} шт.</b>\n\n"
        "Можете дописать описание или прикрепить ещё скриншоты, "
        "а затем нажмите <b>«✅ Отправить репорт»</b>:"
    )


def _build_draft_keyboard(can_submit: bool) -> InlineKeyboardMarkup:
    rows = []
    if can_submit:
        rows.append([
            InlineKeyboardButton(text="✅ Отправить репорт", callback_data="bug_submit"),
        ])
    rows.append([
        InlineKeyboardButton(text="❌ Отмена", callback_data="bug_cancel"),
    ])
    return InlineKeyboardMarkup(inline_keyboard=rows)


async def start_bug_report_flow(
    message: Message,
    state: FSMContext,
    friend_token: Optional[str] = None,
    tg_user_id: Optional[int] = None,
    tg_username: Optional[str] = None,
):
    resolved_tg_id = tg_user_id or (message.from_user.id if message.from_user else 0)
    resolved_tg_name = tg_username or (message.from_user.username if message.from_user else None) or "Гость"

    profile = None
    if friend_token:
        profile = supabase_client.get_profile_by_code_or_tag(friend_token)
    if not profile and resolved_tg_id:
        profile = supabase_client.get_profile_by_tg_id(resolved_tg_id)

    await state.set_state(BugReportStates.waiting_for_report)
    await state.update_data(
        target_user_id=profile["id"] if profile else "",
        target_username=(
            f"{profile.get('username')}{profile.get('tag') or ''}"
            if profile
            else resolved_tg_name
        ),
        friend_code=profile.get("friend_code") if profile else (friend_token or ""),
        texts=[],
        media=[],
        status_msg_id=None,
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
        "Отправьте описание проблемы и любые скриншоты/видео (можно несколькими сообщениями или альбомом). "
        "Когда всё будет готово, нажмите <b>«✅ Отправить репорт»</b>!"
        f"{unlinked_hint}",
        parse_mode="HTML",
        reply_markup=_build_draft_keyboard(can_submit=False),
    )


@router.message(Command("bug"))
async def cmd_bug(message: Message, state: FSMContext):
    await start_bug_report_flow(
        message,
        state,
        tg_user_id=message.from_user.id if message.from_user else None,
        tg_username=message.from_user.username if message.from_user else None,
    )


@router.callback_query(F.data == "report_bug")
async def cb_report_bug(callback: CallbackQuery, state: FSMContext):
    await callback.answer()
    if callback.message:
        await start_bug_report_flow(
            callback.message,
            state,
            tg_user_id=callback.from_user.id,
            tg_username=callback.from_user.username,
        )


@router.callback_query(F.data == "bug_cancel")
async def cb_cancel_bug(callback: CallbackQuery, state: FSMContext):
    await state.clear()
    await callback.answer("Отменено")
    if callback.message:
        try:
            await callback.message.edit_text("❌ Отправка баг-репорта отменена.")
        except Exception:
            await callback.message.answer("❌ Отправка баг-репорта отменена.")


@router.message(BugReportStates.waiting_for_report)
async def collect_bug_part(message: Message, state: FSMContext):
    tg_id = message.from_user.id if message.from_user else 0
    lock = _get_user_lock(tg_id)

    async with lock:
        data = await state.get_data()
        texts: list[str] = list(data.get("texts") or [])
        media: list[tuple[str, str]] = [tuple(m) for m in (data.get("media") or [])]
        status_msg_id: Optional[int] = data.get("status_msg_id")

        text_part = (message.text or message.caption or "").strip()
        if text_part:
            texts.append(text_part)

        if message.photo:
            media.append(("photo", message.photo[-1].file_id))
        elif message.video:
            media.append(("video", message.video.file_id))
        elif message.document:
            media.append(("document", message.document.file_id))

        if not texts and not media:
            await message.answer(
                "Пожалуйста, отправьте текст, скриншот или видео с описанием проблемы."
            )
            return

        draft_text = _build_draft_text(texts, media)
        draft_kb = _build_draft_keyboard(can_submit=True)

        edited = False
        if status_msg_id and message.bot:
            try:
                await message.bot.edit_message_text(
                    chat_id=message.chat.id,
                    message_id=status_msg_id,
                    text=draft_text,
                    parse_mode="HTML",
                    reply_markup=draft_kb,
                )
                edited = True
            except Exception:
                edited = False

        if not edited:
            sent = await message.answer(
                draft_text,
                parse_mode="HTML",
                reply_markup=draft_kb,
            )
            status_msg_id = sent.message_id

        await state.update_data(
            texts=texts,
            media=media,
            status_msg_id=status_msg_id,
        )


@router.callback_query(F.data == "bug_submit")
async def cb_submit_bug(callback: CallbackQuery, state: FSMContext):
    data = await state.get_data()
    texts: list[str] = list(data.get("texts") or [])
    media: list[tuple[str, str]] = [tuple(m) for m in (data.get("media") or [])]

    if not texts and not media:
        await callback.answer(
            "Сначала опишите баг или прикрепите скриншот!",
            show_alert=True,
        )
        return

    await callback.answer("Отправляем репорт...")

    user_id = str(data.get("target_user_id") or "")
    username = str(
        data.get("target_username")
        or (callback.from_user.username if callback.from_user else None)
        or "Пользователь"
    )
    friend_code = str(data.get("friend_code") or "")
    tg_id = callback.from_user.id if callback.from_user else 0
    description = "\n\n".join(texts).strip()

    report_id = "local"
    try:
        res = (
            supabase.table("bug_reports")
            .insert({
                "user_id": user_id or None,
                "telegram_id": tg_id,
                "username": username,
                "description": description or f"[Вложений: {len(media)} шт., без текста]",
                "status": "pending",
            })
            .execute()
        )
        if res.data and isinstance(res.data, list):
            report_id = str(res.data[0].get("id") or "local")
    except Exception as e:
        logger.warning(f"[BugReport] Insert failed: {e}")

    await state.clear()

    done_text = (
        "✅ <b>Баг-репорт отправлен разработчику!</b>\n\n"
        "Если баг подтвердится, вы автоматически получите редкий значок "
        "<b>«Кодинг-хакер»</b> в профиле SyncPai."
    )
    if callback.message:
        try:
            await callback.message.edit_text(done_text, parse_mode="HTML")
        except Exception:
            await callback.message.answer(done_text, parse_mode="HTML")

    admin_text = (
        f"🐞 <b>Новый баг-репорт #{html.escape(report_id)}</b>\n\n"
        f"• <b>Пользователь:</b> {html.escape(username)} (TG ID: <code>{tg_id}</code>)\n"
        f"• <b>Код дружбы:</b> <code>{html.escape(friend_code or '—')}</code>\n"
        f"• <b>Profile ID:</b> <code>{html.escape(user_id or 'не привязан')}</code>\n"
        f"• <b>Вложений:</b> {len(media)} шт.\n"
        f"• <b>Описание:</b>\n{html.escape(description or 'Без текста')}"
    )
    admin_kb = InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(
                text="✅ Подтвердить баг (Выдать Хакера)",
                callback_data=f"bug_approve:{report_id}:{user_id}:{tg_id}",
            )
        ],
        [
            InlineKeyboardButton(
                text="❌ Не баг (Стандартный ответ)",
                callback_data=f"bug_not_bug:{report_id}:{tg_id}",
            )
        ],
        [
            InlineKeyboardButton(
                text="💬 Написать свой ответ",
                callback_data=f"bug_reply:{report_id}:{tg_id}",
            )
        ],
    ])

    bot = callback.bot
    if not bot:
        return

    admin_tg_ids = _resolve_admin_tg_ids()
    for admin_chat_id in admin_tg_ids:
        try:
            if len(media) > 1:
                pv_items = [
                    InputMediaPhoto(media=fid)
                    if mtype == "photo"
                    else InputMediaVideo(media=fid)
                    for mtype, fid in media
                    if mtype in ("photo", "video")
                ]
                doc_items = [
                    InputMediaDocument(media=fid)
                    for mtype, fid in media
                    if mtype == "document"
                ]
                for chunk_start in range(0, len(pv_items), 10):
                    await bot.send_media_group(
                        chat_id=admin_chat_id,
                        media=pv_items[chunk_start : chunk_start + 10],
                    )
                for chunk_start in range(0, len(doc_items), 10):
                    await bot.send_media_group(
                        chat_id=admin_chat_id,
                        media=doc_items[chunk_start : chunk_start + 10],
                    )
                await bot.send_message(
                    chat_id=admin_chat_id,
                    text=admin_text,
                    parse_mode="HTML",
                    reply_markup=admin_kb,
                )
            elif len(media) == 1:
                mtype, fid = media[0]
                caption = admin_text if len(admin_text) <= 1024 else None
                if mtype == "photo":
                    await bot.send_photo(
                        chat_id=admin_chat_id,
                        photo=fid,
                        caption=caption,
                        parse_mode="HTML" if caption else None,
                        reply_markup=admin_kb if caption else None,
                    )
                elif mtype == "video":
                    await bot.send_video(
                        chat_id=admin_chat_id,
                        video=fid,
                        caption=caption,
                        parse_mode="HTML" if caption else None,
                        reply_markup=admin_kb if caption else None,
                    )
                else:
                    await bot.send_document(
                        chat_id=admin_chat_id,
                        document=fid,
                        caption=caption,
                        parse_mode="HTML" if caption else None,
                        reply_markup=admin_kb if caption else None,
                    )
                if not caption:
                    await bot.send_message(
                        chat_id=admin_chat_id,
                        text=admin_text,
                        parse_mode="HTML",
                        reply_markup=admin_kb,
                    )
            else:
                await bot.send_message(
                    chat_id=admin_chat_id,
                    text=admin_text,
                    parse_mode="HTML",
                    reply_markup=admin_kb,
                )
        except Exception as e:
            logger.warning(f"[BugReport] Admin forward error to {admin_chat_id}: {e}")


@router.callback_query(F.data.startswith("bug_approve:"))
async def cb_approve_bug(callback: CallbackQuery):
    if callback.from_user.id not in _resolve_admin_tg_ids():
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
                    "👾 <b>Спасибо! Баг подтверждён!</b>\n\n"
                    "Можете заглянуть у себя в профиль SyncPai через час (или перезапустить приложение) — "
                    "у вас откроются эксклюзивный значок, фон и рамка <b>«Кодинг-хакер»</b>!"
                ),
                parse_mode="HTML",
            )
        except Exception:
            pass


@router.callback_query(F.data.startswith("bug_not_bug:"))
async def cb_not_bug(callback: CallbackQuery):
    if callback.from_user.id not in _resolve_admin_tg_ids():
        await callback.answer("Недостаточно прав", show_alert=True)
        return

    parts = (callback.data or "").split(":")
    report_id = parts[1] if len(parts) > 1 else ""
    tg_id = int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0

    if report_id and report_id != "local":
        try:
            supabase.table("bug_reports").update(
                {"status": "rejected"}
            ).eq("id", report_id).execute()
        except Exception:
            pass

    await callback.answer("Стандартный ответ отправлен")
    if callback.message:
        await callback.message.edit_reply_markup(reply_markup=None)
        await callback.message.reply("❌ Отмечено как «Не баг» (ответ отправлен пользователю).")

    if tg_id > 0 and callback.bot:
        try:
            await callback.bot.send_message(
                chat_id=tg_id,
                text=(
                    "🙏 Спасибо за сообщение! Мы проверили — это штатная работа приложения "
                    "(не баг), но мы всё равно ценим вашу внимательность!"
                ),
            )
        except Exception:
            pass


@router.callback_query(F.data.startswith("bug_reply:"))
async def cb_start_admin_reply(callback: CallbackQuery, state: FSMContext):
    if callback.from_user.id not in _resolve_admin_tg_ids():
        await callback.answer("Недостаточно прав", show_alert=True)
        return

    parts = (callback.data or "").split(":")
    report_id = parts[1] if len(parts) > 1 else ""
    tg_id = int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0

    if tg_id <= 0:
        await callback.answer("Не указан Telegram ID пользователя", show_alert=True)
        return

    await state.set_state(AdminReplyStates.waiting_for_reply_text)
    await state.update_data(reply_report_id=report_id, reply_tg_id=tg_id)
    await callback.answer()
    if callback.message:
        await callback.message.reply(
            f"💬 Введите ответ пользователю (TG ID: <code>{tg_id}</code>) по репорту #{html.escape(report_id)}:",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="❌ Отмена", callback_data="bug_cancel")],
            ]),
        )


@router.message(AdminReplyStates.waiting_for_reply_text)
async def process_admin_reply_text(message: Message, state: FSMContext):
    if not message.from_user or message.from_user.id not in _resolve_admin_tg_ids():
        await state.clear()
        return

    reply_text = (message.text or message.caption or "").strip()
    if not reply_text:
        await message.answer("Введите текстовое сообщение для отправки пользователю.")
        return

    data = await state.get_data()
    report_id = str(data.get("reply_report_id") or "")
    tg_id = int(data.get("reply_tg_id") or 0)
    await state.clear()

    if tg_id > 0 and message.bot:
        try:
            await message.bot.send_message(
                chat_id=tg_id,
                text=(
                    f"💬 <b>Ответ от поддержки SyncPai</b> (репорт #{html.escape(report_id)}):\n\n"
                    f"{html.escape(reply_text)}"
                ),
                parse_mode="HTML",
            )
            await message.answer("✅ Ответ отправлен пользователю!")
        except Exception as e:
            await message.answer(f"⚠️ Не удалось отправить ответ: {e}")


@router.callback_query(F.data.startswith("bug_reject:"))
async def cb_reject_bug(callback: CallbackQuery):
    if callback.from_user.id not in _resolve_admin_tg_ids():
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
