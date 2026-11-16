from aiogram import Router, F
from aiogram.filters import CommandStart, Command
from aiogram.types import Message, CallbackQuery, InlineKeyboardMarkup, InlineKeyboardButton
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import StatesGroup, State

from db import supabase_client

router = Router(name="start_profile")


class LinkProfileState(StatesGroup):
    waiting_for_code = State()


def get_profile_card_text(profile: dict) -> str:
    username = profile.get("username", "Отаку")
    tag = profile.get("tag", "#0001")
    friend_code = profile.get("friend_code", "Не указан")
    tier = profile.get("supporter_tier", "free")
    expires = profile.get("supporter_until")
    bio = profile.get("bio") or "—"
    status = profile.get("custom_status") or "—"

    tier_labels = {
        "free": "Базовый (Free)",
        "supporter": "⚡ SyncPai Plus",
        "vip": "✨ SyncPai Pro",
        "producer": "👑 Founders Club",
    }
    tier_title = tier_labels.get(tier, tier)

    text = (
        f"🌸 <b>Профиль SyncPai</b>\n\n"
        f"👤 <b>Никнейм:</b> {username}{tag}\n"
        f"🔑 <b>Код дружбы:</b> <code>{friend_code}</code>\n"
        f"💎 <b>Статус поддержки:</b> <b>{tier_title}</b>\n"
    )
    if expires:
        text += f"⏳ <b>Действует до:</b> {expires[:10]}\n"
    text += f"💬 <b>Статус:</b> <i>{status}</i>\n"
    text += f"📝 <b>О себе:</b> <i>{bio}</i>\n"
    return text


@router.message(CommandStart())
async def cmd_start(message: Message, state: FSMContext):
    await state.clear()
    tg_id = message.from_user.id
    profile = supabase_client.get_profile_by_tg_id(tg_id)

    # Проверка deep link: /start link_SP123456
    command_args = message.text.split(maxsplit=1)
    if len(command_args) > 1:
        payload = command_args[1].strip()
        if payload.startswith("link_"):
            target_code = payload.replace("link_", "")
            found = supabase_client.get_profile_by_code_or_tag(target_code)
            if found:
                ok = supabase_client.link_profile_telegram(
                    profile_id=found["id"],
                    tg_id=tg_id,
                    tg_username=message.from_user.username,
                )
                if ok:
                    await message.answer(
                        f"✅ <b>Аккаунт успешно привязан!</b>\n\n"
                        f"Добро пожаловать в SyncPai, <b>{found.get('username')}</b>!\n"
                        f"Теперь вам доступны уведомления, продление подписок и загрузка актуальных сборок.",
                        parse_mode="HTML",
                        reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                            [InlineKeyboardButton(text="👤 Мой профиль", callback_data="view_profile")],
                            [InlineKeyboardButton(text="💎 Поддержать SyncPai", callback_data="show_tiers")],
                            [InlineKeyboardButton(text="📥 Скачать приложение", callback_data="download_app")],
                        ])
                    )
                    return

    if profile:
        await message.answer(
            f"👋 С возвращением, <b>{profile.get('username', 'Друг')}</b>!\n"
            f"Ваш Telegram уже привязан к профилю SyncPai.\n\n"
            f"Чем могу помочь?",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="👤 Мой профиль", callback_data="view_profile")],
                [InlineKeyboardButton(text="💎 Поддержать проект", callback_data="show_tiers")],
                [InlineKeyboardButton(text="📥 Скачать SyncPai (.apk / .exe)", callback_data="download_app")],
            ])
        )
    else:
        await message.answer(
            "👋 Привет! Я официальный бот <b>SyncPai</b> — приложения для совместного просмотра аниме.\n\n"
            "Здесь вы можете:\n"
            "• Привязать аккаунт SyncPai по коду дружбы (<code>SP-XXXXXX</code>) или <code>Никнейм#Тег</code>\n"
            "• Оформить или продлить статус <b>SyncPai Plus / Pro / Founder</b>\n"
            "• Скачать самые свежие версии для Windows и Android\n\n"
            "Для начала работы привяжите ваш аккаунт:",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="🔗 Привязать аккаунт", callback_data="link_account")],
                [InlineKeyboardButton(text="📥 Скачать приложение", callback_data="download_app")],
                [InlineKeyboardButton(text="💎 Уровни поддержки", callback_data="show_tiers")],
            ])
        )


@router.callback_query(F.data == "link_account")
async def cb_link_account(callback: CallbackQuery, state: FSMContext):
    await state.set_state(LinkProfileState.waiting_for_code)
    await callback.message.edit_text(
        "📝 Введите ваш <b>Код дружбы</b> из профиля SyncPai (например: <code>SP-ABC123</code>)\n"
        "или ваш <code>Никнейм#1234</code>:",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="❌ Отмена", callback_data="cancel_action")]
        ])
    )
    await callback.answer()


@router.message(LinkProfileState.waiting_for_code)
async def process_profile_code(message: Message, state: FSMContext):
    code = message.text.strip()
    profile = supabase_client.get_profile_by_code_or_tag(code)

    if not profile:
        await message.answer(
            "❌ Профиль с таким кодом или никнеймом не найден в базе SyncPai.\n"
            "Пожалуйста, проверьте код во вкладке <b>Профиль</b> приложения и попробуйте снова:",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="❌ Отмена", callback_data="cancel_action")]
            ])
        )
        return

    ok = supabase_client.link_profile_telegram(
        profile_id=profile["id"],
        tg_id=message.from_user.id,
        tg_username=message.from_user.username,
    )
    await state.clear()

    if ok:
        await message.answer(
            f"🎉 <b>Профиль успешно привязан!</b>\n\n"
            f"{get_profile_card_text(profile)}",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="💎 Поддержать SyncPai", callback_data="show_tiers")],
                [InlineKeyboardButton(text="📥 Скачать приложение", callback_data="download_app")],
            ])
        )
    else:
        await message.answer("⚠️ Не удалось связать профиль. Попробуйте позже или напишите администратору.")


@router.message(Command("profile"))
@router.callback_query(F.data == "view_profile")
async def show_profile(event: Message | CallbackQuery):
    tg_id = event.from_user.id
    profile = supabase_client.get_profile_by_tg_id(tg_id)

    if not profile:
        text = (
            "⚠️ Ваш Telegram пока не привязан к профилю SyncPai.\n\n"
            "Нажмите кнопку ниже, чтобы привязать:"
        )
        kb = InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="🔗 Привязать аккаунт", callback_data="link_account")]
        ])
    else:
        text = get_profile_card_text(profile)
        kb = InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="💎 Улучшить / Продлить подписку", callback_data="show_tiers")],
            [InlineKeyboardButton(text="🔓 Отвязать аккаунт", callback_data="unlink_account")],
        ])

    if isinstance(event, CallbackQuery):
        await event.message.edit_text(text, parse_mode="HTML", reply_markup=kb)
        await event.answer()
    else:
        await event.answer(text, parse_mode="HTML", reply_markup=kb)


@router.callback_query(F.data == "unlink_account")
async def cb_unlink_account(callback: CallbackQuery):
    profile = supabase_client.get_profile_by_tg_id(callback.from_user.id)
    if profile:
        supabase_client.unlink_profile_telegram(profile["id"])
    await callback.message.edit_text(
        "👋 Аккаунт SyncPai отвязан от этого Telegram-чата.\n"
        "Вы всегда можете привязать его заново командой /start.",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="🔗 Привязать снова", callback_data="link_account")]
        ])
    )
    await callback.answer()


@router.callback_query(F.data == "cancel_action")
async def cb_cancel_action(callback: CallbackQuery, state: FSMContext):
    await state.clear()
    await callback.message.edit_text(
        "Действие отменено. Главное меню:",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="👤 Мой профиль", callback_data="view_profile")],
            [InlineKeyboardButton(text="💎 Поддержать SyncPai", callback_data="show_tiers")],
            [InlineKeyboardButton(text="📥 Скачать приложение", callback_data="download_app")],
        ])
    )
    await callback.answer()

