import logging
from aiogram import Router, F
from aiogram.filters import Command
from aiogram.types import Message, CallbackQuery, InlineKeyboardMarkup, InlineKeyboardButton
from config import settings
from db import supabase_client
from handlers.support_payments import TIERS_DATA

logger = logging.getLogger(__name__)
router = Router(name="admin")


def is_admin(user_id: int) -> bool:
    return user_id == settings.admin_telegram_id


@router.message(Command("admin"))
async def cmd_admin(message: Message):
    if not is_admin(message.from_user.id):
        await message.answer("⛔ Доступ разрешён только владельцу проекта.")
        return

    text = (
        "🛡 <b>Панель администратора SyncPai</b>\n\n"
        "Доступные команды:\n"
        "• <code>/grant &lt;SP-CODE / USER_ID&gt; &lt;supporter|vip|producer&gt; [дни]</code> — выдать статус вручную\n"
        "• <code>/revoke &lt;SP-CODE / USER_ID&gt;</code> — сбросить статус на free\n"
        "• <code>/stats</code> — статистика пользователей и саппортеров"
    )

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📊 Статистика", callback_data="admin_stats")],
        [InlineKeyboardButton(text="💎 Список активных саппортеров", callback_data="admin_list_supporters")],
    ])

    await message.answer(text, parse_mode="HTML", reply_markup=kb)


@router.callback_query(F.data == "admin_stats")
async def cb_admin_stats(callback: CallbackQuery):
    if not is_admin(callback.from_user.id):
        await callback.answer("⛔ Нет доступа", show_alert=True)
        return

    try:
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

        text = (
            f"📊 <b>Статистика SyncPai:</b>\n\n"
            f"👥 Всего пользователей: <b>{total_users}</b>\n"
            f"💎 Активных платных подписок: <b>{len(supporters)}</b>\n"
            f"  • ⚡ SyncPai Plus: <b>{count_plus}</b>\n"
            f"  • ✨ SyncPai Pro: <b>{count_pro}</b>\n"
            f"  • 👑 Founders Club: <b>{count_founders}</b>\n"
        )
        await callback.message.edit_text(text, parse_mode="HTML", reply_markup=InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="◀️ Назад", callback_data="admin_back")]
        ]))
    except Exception as e:
        await callback.answer(f"Ошибка загрузки: {e}", show_alert=True)


@router.callback_query(F.data == "admin_list_supporters")
async def cb_admin_list_supporters(callback: CallbackQuery):
    if not is_admin(callback.from_user.id):
        await callback.answer("⛔ Нет доступа", show_alert=True)
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
                    [InlineKeyboardButton(text="◀️ Назад", callback_data="admin_back")]
                ])
            )
            return

        lines = ["💎 <b>Активные саппортеры:</b>\n"]
        for row in data:
            until = (row.get("supporter_until") or "")[:10]
            lines.append(f"• <b>{row.get('username')}{row.get('tag')}</b> [{row.get('supporter_tier')}] (до {until})")

        await callback.message.edit_text(
            "\n".join(lines),
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="◀️ Назад", callback_data="admin_back")]
            ])
        )
    except Exception as e:
        await callback.answer(f"Ошибка: {e}", show_alert=True)


@router.callback_query(F.data == "admin_back")
async def cb_admin_back(callback: CallbackQuery):
    if not is_admin(callback.from_user.id):
        return
    await cmd_admin(callback.message)
    await callback.answer()


@router.callback_query(F.data.startswith("admin_approve_"))
async def cb_admin_approve(callback: CallbackQuery):
    if not is_admin(callback.from_user.id):
        await callback.answer("⛔ Только для администратора", show_alert=True)
        return

    # format: admin_approve_{target_tg_id}_{tier_id}_{profile_id}
    parts = callback.data.split("_")
    target_tg_id = int(parts[2])
    tier_id = parts[3]
    profile_id = parts[4]

    info = TIERS_DATA.get(tier_id, TIERS_DATA["supporter"])
    days = info["days"]

    # Если profile_id неизвестен (пользователь не привязал до чека), ищем по target_tg_id
    if profile_id == "none" or not profile_id:
        p = supabase_client.get_profile_by_tg_id(target_tg_id)
        if p:
            profile_id = p["id"]

    if profile_id and profile_id != "none":
        supabase_client.set_supporter_tier(profile_id, tier_id, days=days)
        success_msg = f"✅ Уровень <b>{info['title']}</b> успешно активирован на <b>{days} дней</b>!"
    else:
        success_msg = f"⚠️ Уровень одобрен, но профиль SyncPai не найден в базе. Пользователь должен привязать аккаунт через /start."

    # Уведомляем пользователя
    try:
        await callback.bot.send_message(
            chat_id=target_tg_id,
            text=(
                f"🎉 <b>Платёж подтверждён администратором!</b>\n\n"
                f"Вам начислен статус <b>{info['title']}</b> на <b>{days} дней</b>.\n"
                f"Спасибо, что делаете SyncPai лучше! 💖\n"
                f"Перезапустите приложение, чтобы активировать все возможности."
            ),
            parse_mode="HTML"
        )
    except Exception as e:
        logger.warning(f"Could not notify user {target_tg_id}: {e}")

    await callback.message.edit_caption(
        caption=(callback.message.caption or "") + f"\n\n<b>[ОДОБРЕНО АДМИНИСТРАТОРОМ]</b>\n{success_msg}",
        parse_mode="HTML",
        reply_markup=None,
    )
    await callback.answer("Платёж подтверждён!")


@router.callback_query(F.data.startswith("admin_reject_"))
async def cb_admin_reject(callback: CallbackQuery):
    if not is_admin(callback.from_user.id):
        await callback.answer("⛔ Только для администратора", show_alert=True)
        return

    target_tg_id = int(callback.data.split("_")[2])

    try:
        await callback.bot.send_message(
            chat_id=target_tg_id,
            text=(
                "❌ <b>Квитанция отклонена администратором.</b>\n\n"
                "Если произошла ошибка или вы перевели средства, пожалуйста, "
                "напишите в поддержку проекта напрямую."
            ),
            parse_mode="HTML"
        )
    except Exception as e:
        logger.warning(f"Could not notify user {target_tg_id}: {e}")

    await callback.message.edit_caption(
        caption=(callback.message.caption or "") + "\n\n<b>[ОТКЛОНЕНО]</b>",
        parse_mode="HTML",
        reply_markup=None,
    )
    await callback.answer("Отклонено")


@router.message(Command("grant"))
async def cmd_grant(message: Message):
    if not is_admin(message.from_user.id):
        return

    parts = message.text.split()
    if len(parts) < 3:
        await message.answer("Использование: <code>/grant &lt;SP-CODE / ID&gt; &lt;supporter|vip|producer&gt; [дни]</code>", parse_mode="HTML")
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
        await message.answer(f"✅ Пользователю <b>{profile.get('username')}</b> выдан <b>{tier}</b> на {days} дней.", parse_mode="HTML")
        if profile.get("telegram_id"):
            try:
                await message.bot.send_message(
                    chat_id=profile["telegram_id"],
                    text=f"🎁 Администратор активировал вам уровень <b>{tier}</b> на {days} дней!",
                    parse_mode="HTML"
                )
            except Exception:
                pass
    else:
        await message.answer("Ошибка при обновлении профиля.")

