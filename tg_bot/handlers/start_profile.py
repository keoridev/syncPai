import html
from aiogram import F, Router
from aiogram.filters import Command, CommandObject, CommandStart
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import CallbackQuery, InlineKeyboardButton, InlineKeyboardMarkup, Message

from db import supabase_client
from services.card_renderer import send_or_edit_card

router = Router(name="start_profile")


class LinkProfileState(StatesGroup):
    waiting_for_code = State()


def get_profile_card_text(profile: dict) -> str:
    username = html.escape(str(profile.get("username") or "Пользователь"))
    raw_tag = str(profile.get("tag") or "#0001")
    tag = html.escape(raw_tag if raw_tag.startswith("#") else f"#{raw_tag}")
    friend_code = html.escape(str(profile.get("friend_code") or "Не указан"))
    tier = profile.get("supporter_tier", "free")
    expires = profile.get("supporter_until")
    bio = html.escape(str(profile.get("bio") or "—"))
    status = html.escape(str(profile.get("custom_status") or "—"))

    tier_labels = {
        "free": "Базовый (Free)",
        "supporter": "SyncPai Plus",
        "vip": "SyncPai Pro",
        "producer": "Founders Club (Навсегда)",
    }
    tier_title = tier_labels.get(tier, str(tier))

    text = (
        f"<b>Профиль SyncPai</b>\n\n"
        f"• <b>Никнейм:</b> {username}{tag}\n"
        f"• <b>Код дружбы:</b> <code>{friend_code}</code>\n"
        f"• <b>Уровень поддержки:</b> <b>{tier_title}</b>\n"
    )
    if tier == "producer" or (expires and str(expires).startswith("2099")):
        text += "• <b>Срок действия:</b> Навсегда (Бессрочно)\n"
    elif expires:
        text += f"• <b>Действует до:</b> {str(expires)[:10]}\n"
    text += f"• <b>Статус:</b> <i>{status}</i>\n"
    text += f"• <b>О себе:</b> <i>{bio}</i>"
    return text


def _linked_menu_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="Мой профиль", callback_data="view_profile")],
        [InlineKeyboardButton(text="Заказать фичу (7 дней)", callback_data="menu:order_feature")],
        [InlineKeyboardButton(text="Уровни поддержки (от 99 сом)", callback_data="show_tiers")],
        [InlineKeyboardButton(text="Мои заявки", callback_data="menu:my_requests")],
        [InlineKeyboardButton(text="Скачать приложение", callback_data="download_app")],
        [InlineKeyboardButton(text="Нашел баг", callback_data="report_bug")],
    ])


def _guest_menu_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="Привязать аккаунт", callback_data="link_account")],
        [InlineKeyboardButton(text="Заказать фичу (7 дней)", callback_data="menu:order_feature")],
        [InlineKeyboardButton(text="Уровни поддержки (от 99 сом)", callback_data="show_tiers")],
        [InlineKeyboardButton(text="Скачать приложение", callback_data="download_app")],
        [InlineKeyboardButton(text="Нашел баг", callback_data="report_bug")],
    ])


@router.message(CommandStart())
async def cmd_start(message: Message, command: CommandObject, state: FSMContext):
    await state.clear()
    tg_id = message.from_user.id
    profile = supabase_client.get_profile_by_tg_id(tg_id)

    # Проверка deep link: /start feat_<uid>, /start duo_<code>, /start bug_..., /start gift_...
    args = (command.args or "").strip()
    if args.startswith("feat_"):
        from handlers.feature_requests import start_feature_flow

        user_id = args.removeprefix("feat_").strip()
        await start_feature_flow(message, state, user_id=user_id)
        return

    if args.startswith("duo_"):
        from handlers.feature_requests import handle_duo_invite

        invite_code = args.removeprefix("duo_").strip()
        await handle_duo_invite(message, state, invite_code=invite_code)
        return

    if args.startswith("bug_"):
        from handlers.bug_report import start_bug_report_flow

        friend_token = args.removeprefix("bug_").strip()
        await start_bug_report_flow(message, state, friend_token=friend_token)
        return

    if args.startswith("gift_"):
        gift_token = args.removeprefix("gift_").strip()
        if gift_token:
            found = supabase_client.get_profile_by_code_or_tag(gift_token)
            if found:
                uname = html.escape(str(found.get("username") or "Пользователь"))
                raw_tag = str(found.get("tag") or "")
                tag = html.escape(f"#{raw_tag.lstrip('#')}" if raw_tag else "")
                fcode = html.escape(str(found.get("friend_code") or gift_token))
                recipient_display = f"{uname}{tag}"
                await state.update_data(
                    gift_recipient_id=found["id"],
                    gift_recipient_name=recipient_display,
                    gift_recipient_code=fcode,
                    gift_recipient_tg_id=found.get("telegram_id"),
                )
                await send_or_edit_card(
                    message,
                    card_key="support",
                    caption=(
                        f"<b>Подарок для {recipient_display}</b>\n"
                        f"• Код дружбы: <code>{fcode}</code>\n\n"
                        f"Выбери уровень подписки, который хочешь подарить:"
                    ),
                    reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                        [InlineKeyboardButton(text="Plus — 55 ⭐ (99 сом)", callback_data="gift_tier_supporter")],
                        [InlineKeyboardButton(text="Pro — 110 ⭐ (199 сом)", callback_data="gift_tier_vip")],
                        [InlineKeyboardButton(text="Founders (Навсегда) — 270 ⭐ (490 сом)", callback_data="gift_tier_producer")],
                        [InlineKeyboardButton(text="← Назад к тарифам", callback_data="show_tiers")],
                    ]),
                )
                return

    if args == "buy_duo":
        await send_or_edit_card(
            message,
            card_key="support",
            caption=(
                "<b>Парный пак (Duo) — SyncPai</b>\n\n"
                "• Анимированные парные диптихи и пульсирующие кольца\n"
                "• Автоматическая синхронизация оформления для обоих партнёров\n"
                "• Стоимость: <b>85 ⭐ (149 сом)</b>\n\n"
                "Оформить можно через SyncPai Plus или напрямую через Telegram Stars:"
            ),
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="Открыть тарифы (от 55 ⭐)", callback_data="show_tiers")],
                [InlineKeyboardButton(text="← Меню", callback_data="cancel_action")],
            ]),
        )
        return

    if args.startswith("link_"):
        link_token = args.removeprefix("link_").strip()
        if link_token:
            found = supabase_client.get_profile_by_code_or_tag(link_token)
            if found:
                ok = supabase_client.link_profile_telegram(
                    profile_id=found["id"],
                    tg_id=tg_id,
                    tg_username=message.from_user.username,
                )
                if ok:
                    uname = html.escape(str(found.get("username") or "Пользователь"))
                    raw_tag = str(found.get("tag") or "#0001")
                    tag = html.escape(raw_tag if raw_tag.startswith("#") else f"#{raw_tag}")
                    await send_or_edit_card(
                        message,
                        card_key="welcome",
                        caption=(
                            f"Аккаунт <b>{uname}{tag}</b> успешно привязан! "
                            f"Теперь можно оформлять подписку или управлять профилем прямо здесь."
                        ),
                        reply_markup=_linked_menu_keyboard(),
                    )
                    return

    if profile:
        uname = html.escape(str(profile.get("username") or "Пользователь"))
        await send_or_edit_card(
            message,
            card_key="welcome",
            caption=(
                f"<b>С возвращением, {uname}</b>\n\n"
                f"Твой Telegram уже привязан к SyncPai. Выбирай, что откроем:"
            ),
            reply_markup=_linked_menu_keyboard(),
        )
    else:
        await send_or_edit_card(
            message,
            card_key="welcome",
            caption=(
                "<b>Привет! Я Пай-тян — помощник SyncPai</b>\n\n"
                "Здесь ты можешь:\n"
                "• Привязать аккаунт по коду дружбы (<code>SP-XXXXXX</code>) или <code>Ник#Тег</code>\n"
                "• Открыть уровни поддержки — <b>Plus</b>, <b>Pro</b> и <b>Founders Club</b>\n"
                "• Скачать актуальные версии для Windows и Android"
            ),
            reply_markup=_guest_menu_keyboard(),
        )


@router.message(Command("link"))
@router.callback_query(F.data == "link_account")
async def cb_link_account(event: Message | CallbackQuery, state: FSMContext):
    await state.set_state(LinkProfileState.waiting_for_code)
    await send_or_edit_card(
        event,
        card_key="link",
        caption=(
            "<b>Привязка аккаунта SyncPai</b>\n\n"
            "Отправь в чат свой <b>Код дружбы</b> из профиля приложения "
            "(например, <code>SP-XXXXXX</code>) или <code>Ник#Тег</code> (например, <code>keori#5727</code>)."
        ),
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="← Назад", callback_data="cancel_action")],
        ]),
    )


@router.message(LinkProfileState.waiting_for_code, F.text, ~F.text.startswith("/"))
async def process_profile_code(message: Message, state: FSMContext):
    code = (message.text or "").strip()
    profile = supabase_client.get_profile_by_code_or_tag(code)

    if not profile:
        await message.answer(
            "Профиль с таким кодом или тегом не найден.\n"
            "Проверь <code>SP-XXXXXX</code> или <code>Ник#Тег</code> во вкладке <b>Профиль</b> и попробуй ещё раз:",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="Отмена", callback_data="cancel_action")],
            ]),
        )
        return

    ok = supabase_client.link_profile_telegram(
        profile_id=profile["id"],
        tg_id=message.from_user.id,
        tg_username=message.from_user.username,
    )
    await state.clear()

    if ok:
        await send_or_edit_card(
            message,
            card_key="welcome",
            caption=f"<b>Профиль успешно привязан</b>\n\n{get_profile_card_text(profile)}",
            reply_markup=_linked_menu_keyboard(),
        )
    else:
        await message.answer("Не удалось связать профиль. Попробуй чуть позже.")


@router.message(Command("profile"))
@router.callback_query(F.data == "view_profile")
async def show_profile(event: Message | CallbackQuery, state: FSMContext):
    await state.clear()
    tg_id = event.from_user.id
    profile = supabase_client.get_profile_by_tg_id(tg_id)

    if not profile:
        await send_or_edit_card(
            event,
            card_key="link",
            caption=(
                "<b>Профиль ещё не привязан</b>\n\n"
                "Нажми кнопку ниже и отправь свой <code>SP-XXXXXX</code> или <code>Ник#Тег</code>."
            ),
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="Привязать аккаунт", callback_data="link_account")],
                [InlineKeyboardButton(text="← Назад", callback_data="cancel_action")],
            ]),
        )
    else:
        await send_or_edit_card(
            event,
            card_key="welcome",
            caption=get_profile_card_text(profile),
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="Уровни поддержки", callback_data="show_tiers")],
                [InlineKeyboardButton(text="Отвязать аккаунт", callback_data="unlink_account")],
                [InlineKeyboardButton(text="← Назад", callback_data="cancel_action")],
            ]),
        )


@router.callback_query(F.data == "unlink_account")
async def cb_unlink_account(callback: CallbackQuery):
    profile = supabase_client.get_profile_by_tg_id(callback.from_user.id)
    if profile:
        supabase_client.unlink_profile_telegram(profile["id"])
    await send_or_edit_card(
        callback,
        card_key="link",
        caption=(
            "<b>Аккаунт отвязан</b>\n\n"
            "Ты всегда можешь привязать его снова по коду <code>SP-XXXXXX</code> или <code>Ник#Тег</code>."
        ),
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="Привязать аккаунт", callback_data="link_account")],
            [InlineKeyboardButton(text="← Назад", callback_data="cancel_action")],
        ]),
    )


@router.callback_query(F.data == "cancel_action")
async def cb_cancel_action(callback: CallbackQuery, state: FSMContext):
    await state.clear()
    profile = supabase_client.get_profile_by_tg_id(callback.from_user.id)
    if profile:
        uname = html.escape(str(profile.get("username") or "Пользователь"))
        caption = f"<b>Главное меню SyncPai</b>\n\nРада видеть тебя, <b>{uname}</b>. Выбирай раздел:"
        kb = _linked_menu_keyboard()
    else:
        caption = (
            "<b>Главное меню SyncPai</b>\n\n"
            "Привяжи профиль по <code>SP-XXXXXX</code> или <code>Ник#Тег</code>, "
            "посмотри уровни поддержки или скачай приложение."
        )
        kb = _guest_menu_keyboard()

    await send_or_edit_card(
        callback,
        card_key="welcome",
        caption=caption,
        reply_markup=kb,
    )
