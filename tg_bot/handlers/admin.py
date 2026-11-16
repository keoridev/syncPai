import html
import logging
from aiogram import F, Router
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from aiogram.types import CallbackQuery, InlineKeyboardButton, InlineKeyboardMarkup, Message
from config import settings
from db import supabase_client
from handlers.support_payments import TIERS_DATA

logger = logging.getLogger(__name__)
router = Router(name="admin")


def is_admin(user_id: int) -> bool:
    return user_id == settings.admin_telegram_id


def _admin_menu_content() -> tuple[str, InlineKeyboardMarkup]:
    text = (
        "<b>Панель администратора SyncPai</b>\n\n"
        "Доступные команды:\n"
        "• <code>/grant &lt;SP-CODE / USER_ID&gt; &lt;supporter|vip|producer&gt; [дни]</code> — выдать статус вручную\n"
        "• <code>/revoke &lt;SP-CODE / USER_ID&gt;</code> — сбросить статус на free\n"
        "• <code>/stats</code> — статистика пользователей и саппортеров"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="Статистика", callback_data="admin_stats")],
        [InlineKeyboardButton(text="Список активных саппортеров", callback_data="admin_list_supporters")],
    ])
    return text, kb


def _build_stats_text() -> str:
    total_res = supabase_client.supabase.table("profiles").select("id", count="exact").execute()
    total_users = total_res.count or 0

    supporters_res = (
        supabase_client.supabase.table("profiles")
        .select("id, supporter_tier")
        .neq("supporter_tier", "free")
        .execute()
    )
    supporters = supporters_res.data or []
    count_plus = sum(1 for s in supporters if s.get("supporter_tier") == "supporter")
    count_pro = sum(1 for s in supporters if s.get("supporter_tier") == "vip")
    count_founders = sum(1 for s in supporters if s.get("supporter_tier") == "producer")

    return (
        f"<b>Статистика SyncPai</b>\n\n"
        f"• Всего пользователей: <b>{total_users}</b>\n"
        f"• Активных платных подписок: <b>{len(supporters)}</b>\n"
        f"  — SyncPai Plus: <b>{count_plus}</b>\n"
        f"  — SyncPai Pro: <b>{count_pro}</b>\n"
        f"  — Founders Club: <b>{count_founders}</b>"
    )


@router.message(Command("admin"))
async def cmd_admin(message: Message, state: FSMContext):
    await state.clear()
    if not message.from_user or not is_admin(message.from_user.id):
        await message.answer("Доступ разрешён только владельцу проекта.")
        return
    text, kb = _admin_menu_content()
    await message.answer(text, parse_mode="HTML", reply_markup=kb)


@router.message(Command("stats"))
async def cmd_stats(message: Message, state: FSMContext):
    await state.clear()
    if not message.from_user or not is_admin(message.from_user.id):
        await message.answer("Доступ разрешён только владельцу проекта.")
        return
    try:
        text = _build_stats_text()
        await message.answer(text, parse_mode="HTML")
    except Exception as e:
        await message.answer(f"Ошибка загрузки статистики: {html.escape(str(e))}", parse_mode="HTML")


@router.callback_query(F.data == "admin_stats")
async def cb_admin_stats(callback: CallbackQuery):
    if not is_admin(callback.from_user.id):
        await callback.answer("Нет доступа", show_alert=True)
        return

    try:
        text = _build_stats_text()
        await callback.message.edit_text(
            text,
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="← Назад", callback_data="admin_back")]
            ]),
        )
        await callback.answer()
    except Exception as e:
        await callback.answer(f"Ошибка загрузки: {e}", show_alert=True)


@router.callback_query(F.data == "admin_list_supporters")
async def cb_admin_list_supporters(callback: CallbackQuery):
    if not is_admin(callback.from_user.id):
        await callback.answer("Нет доступа", show_alert=True)
        return

    try:
        res = (
            supabase_client.supabase.table("profiles")
            .select("username, tag, supporter_tier, supporter_until, friend_code")
            .neq("supporter_tier", "free")
            .order("supporter_until", desc=False)
            .limit(20)
            .execute()
        )
        data = res.data or []
        if not data:
            await callback.message.edit_text(
                "Список активных саппортеров пуст.",
                reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                    [InlineKeyboardButton(text="← Назад", callback_data="admin_back")]
                ]),
            )
            await callback.answer()
            return

        lines = ["<b>Активные саппортеры:</b>\n"]
        for row in data:
            until = (row.get("supporter_until") or "")[:10]
            uname = html.escape(str(row.get("username") or "Пользователь"))
            tag = html.escape(str(row.get("tag") or ""))
            tier = html.escape(str(row.get("supporter_tier") or ""))
            lines.append(f"• <b>{uname}{tag}</b> [{tier}] (до {until})")

        await callback.message.edit_text(
            "\n".join(lines),
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="← Назад", callback_data="admin_back")]
            ]),
        )
        await callback.answer()
    except Exception as e:
        await callback.answer(f"Ошибка: {e}", show_alert=True)


@router.callback_query(F.data == "admin_back")
async def cb_admin_back(callback: CallbackQuery):
    if not is_admin(callback.from_user.id):
        await callback.answer("Нет доступа", show_alert=True)
        return
    text, kb = _admin_menu_content()
    await callback.message.edit_text(text, parse_mode="HTML", reply_markup=kb)
    await callback.answer()


@router.callback_query(F.data.startswith("admin_approve_"))
async def cb_admin_approve(callback: CallbackQuery):
    if not is_admin(callback.from_user.id):
        await callback.answer("Только для администратора", show_alert=True)
        return

    parts = (callback.data or "").split("_", 4)
    if len(parts) < 5:
        await callback.answer("Некорректные данные чека", show_alert=True)
        return

    target_tg_id = int(parts[2])
    tier_id = parts[3]
    profile_id = parts[4]

    info = TIERS_DATA.get(tier_id, TIERS_DATA["supporter"])
    days = info["days"]

    if profile_id == "none" or not profile_id:
        p = supabase_client.get_profile_by_tg_id(target_tg_id)
        if p:
            profile_id = p["id"]

    if profile_id and profile_id != "none":
        ok = supabase_client.set_supporter_tier(profile_id, tier_id, days=days)
        if ok:
            success_msg = f"Уровень <b>{info['title']}</b> активирован на <b>{days} дней</b>."
        else:
            success_msg = "Не удалось обновить профиль в базе данных."
    else:
        success_msg = "Одобрено, но профиль SyncPai не найден в базе. Пользователь должен привязать аккаунт через /start."

    try:
        await callback.bot.send_message(
            chat_id=target_tg_id,
            text=(
                f"<b>Платёж подтверждён</b>\n\n"
                f"Тебе начислен статус <b>{info['title']}</b> на <b>{days} дней</b>.\n"
                f"Перезапусти приложение SyncPai, чтобы активировать все возможности."
            ),
            parse_mode="HTML",
        )
    except Exception as e:
        logger.warning(f"Could not notify user {target_tg_id}: {e}")

    if callback.message.caption is not None:
        await callback.message.edit_caption(
            caption=f"{callback.message.caption}\n\n<b>[Одобрено]</b>\n{success_msg}",
            parse_mode="HTML",
            reply_markup=None,
        )
    else:
        await callback.message.edit_text(
            text=f"{callback.message.text or ''}\n\n<b>[Одобрено]</b>\n{success_msg}",
            parse_mode="HTML",
            reply_markup=None,
        )
    await callback.answer("Платёж подтверждён")


@router.callback_query(F.data.startswith("admin_reject_"))
async def cb_admin_reject(callback: CallbackQuery):
    if not is_admin(callback.from_user.id):
        await callback.answer("Только для администратора", show_alert=True)
        return

    parts = (callback.data or "").split("_", 2)
    if len(parts) < 3:
        await callback.answer("Некорректные данные", show_alert=True)
        return
    target_tg_id = int(parts[2])

    try:
        await callback.bot.send_message(
            chat_id=target_tg_id,
            text=(
                "<b>Квитанция отклонена администратором</b>\n\n"
                "Если произошла ошибка или средства уже переведены, напиши в поддержку проекта."
            ),
            parse_mode="HTML",
        )
    except Exception as e:
        logger.warning(f"Could not notify user {target_tg_id}: {e}")

    if callback.message.caption is not None:
        await callback.message.edit_caption(
            caption=f"{callback.message.caption}\n\n<b>[Отклонено]</b>",
            parse_mode="HTML",
            reply_markup=None,
        )
    else:
        await callback.message.edit_text(
            text=f"{callback.message.text or ''}\n\n<b>[Отклонено]</b>",
            parse_mode="HTML",
            reply_markup=None,
        )
    await callback.answer("Отклонено")


@router.message(Command("grant"))
async def cmd_grant(message: Message, state: FSMContext):
    await state.clear()
    if not message.from_user or not is_admin(message.from_user.id):
        return

    parts = (message.text or "").split()
    if len(parts) < 3:
        await message.answer(
            "Использование: <code>/grant &lt;SP-CODE / ID&gt; &lt;supporter|vip|producer&gt; [дни]</code>",
            parse_mode="HTML",
        )
        return

    identifier = parts[1]
    tier = parts[2].lower()
    days = int(parts[3]) if len(parts) > 3 and parts[3].isdigit() else 30

    if tier not in ["supporter", "vip", "producer"]:
        await message.answer("Неверный уровень. Доступны: supporter, vip, producer.")
        return

    profile = supabase_client.get_profile_by_code_or_tag(identifier)
    if not profile:
        await message.answer("Пользователь не найден.")
        return

    ok = supabase_client.set_supporter_tier(profile["id"], tier, days=days)
    if ok:
        uname = html.escape(str(profile.get("username") or "Пользователь"))
        await message.answer(
            f"Пользователю <b>{uname}</b> выдан <b>{tier}</b> на {days} дней.",
            parse_mode="HTML",
        )
        if profile.get("telegram_id"):
            try:
                await message.bot.send_message(
                    chat_id=profile["telegram_id"],
                    text=f"Администратор активировал тебе уровень <b>{tier}</b> на {days} дней.",
                    parse_mode="HTML",
                )
            except Exception:
                pass
    else:
        await message.answer("Ошибка при обновлении профиля.")


@router.message(Command("revoke"))
async def cmd_revoke(message: Message, state: FSMContext):
    await state.clear()
    if not message.from_user or not is_admin(message.from_user.id):
        return

    parts = (message.text or "").split()
    if len(parts) < 2:
        await message.answer(
            "Использование: <code>/revoke &lt;SP-CODE / ID&gt;</code>",
            parse_mode="HTML",
        )
        return

    identifier = parts[1]
    profile = supabase_client.get_profile_by_code_or_tag(identifier)
    if not profile:
        await message.answer("Пользователь не найден.")
        return

    ok = supabase_client.downgrade_to_free(profile["id"])
    if ok:
        uname = html.escape(str(profile.get("username") or "Пользователь"))
        await message.answer(
            f"Статус пользователя <b>{uname}</b> сброшен на <b>free</b>.",
            parse_mode="HTML",
        )
        if profile.get("telegram_id"):
            try:
                await message.bot.send_message(
                    chat_id=profile["telegram_id"],
                    text="Твой уровень поддержки SyncPai был сброшен администратором до базового (free).",
                    parse_mode="HTML",
                )
            except Exception:
                pass
    else:
        await message.answer("Ошибка при сбросе статуса профиля.")
