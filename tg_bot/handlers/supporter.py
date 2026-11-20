import html
import logging
from aiogram import F, Router
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import (
    CallbackQuery,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    LabeledPrice,
    Message,
    PreCheckoutQuery,
)

from config import settings
from db import supabase_client
from services.card_renderer import send_or_edit_card

logger = logging.getLogger(__name__)

router = Router(name="supporter")


class ReceiptUploadState(StatesGroup):
    waiting_for_receipt = State()


class GiftStates(StatesGroup):
    waiting_for_friend_code = State()


TIERS_DATA = {
    "supporter": {
        "title": "SyncPai Plus",
        "price_kgs": 99,
        "price_rub": 99,
        "stars": 55,
        "days": 30,
        "days_label": "30 дней",
        "perks": [
            "• Живые анимированные рамки («Северное сияние», «Кибер-импульс») и анимированные шапки",
            "• Расширенная палитра акцентных цветов интерфейса",
            "• Расширенные комнаты Watch Together (до 10 друзей + приоритетная синхронизация)",
            "• Значок саппортера в профиле",
        ],
    },
    "vip": {
        "title": "SyncPai Pro",
        "price_kgs": 199,
        "price_rub": 199,
        "stars": 110,
        "days": 30,
        "days_label": "30 дней",
        "perks": [
            "• Всё из SyncPai Plus",
            "• Топ-3 любимых тайтла на полке в профиле (вместо 1)",
            "• Главная иллюстрация (Steam Artwork / GIF) — загрузка своего арта в витрину",
            "• Кастомный титул профиля под никнеймом",
            "• Экспорт карточки SyncPai Wrapped без водяного знака",
        ],
    },
    "producer": {
        "title": "Founders Club (Навсегда)",
        "price_kgs": 490,
        "price_rub": 490,
        "stars": 270,
        "days": 0,
        "days_label": "Навсегда (разовый платёж)",
        "perks": [
            "• Все возможности SyncPai Pro навсегда без ежемесячных списаний",
            "• Эксклюзивная золотая рамка «Золотой ореол» и значок первопроходца Founders Club",
            "• Имя в титрах благодарности в разделе «О приложении»",
        ],
    },
}


def has_anonymous_alternatives() -> bool:
    """Проверяет, заданы ли в .env анонимные альтернативные методы (Crypto / TON / Tribute)."""
    return bool(
        (settings.pay_crypto_bot_link and settings.pay_crypto_bot_link.strip()) or
        (settings.pay_ton and settings.pay_ton.strip()) or
        (settings.pay_tribute and settings.pay_tribute.strip())
    )


def format_goal_banner() -> str:
    """Генерация прозрачного индикатора цели инфраструктуры."""
    current = settings.monthly_goal_current
    target = settings.monthly_goal_target
    title = settings.monthly_goal_title
    pct = int((current / target) * 100) if target > 0 else 0
    filled = min(10, max(0, round(pct / 10)))
    bar = "█" * filled + "░" * (10 - filled)
    c_str = f"{current:,}".replace(",", " ")
    t_str = f"{target:,}".replace(",", " ")
    return (
        "<b>«SyncPai работает без рекламы и инвесторов»</b>\n"
        "<i>Весь стриминг и совместный просмотр бесплатны. "
        "Подписка помогает оплачивать серверы для бота и ускоряет выход новых функций.</i>\n\n"
        f"🎯 <b>Цель месяца: {title}</b>\n"
        f"<code>[{bar}] {pct}% ({c_str} / {t_str} сом)</code>"
    )


def _build_anonymous_payment_caption(
    tier_info: dict,
    is_gift: bool = False,
    recipient_name: str = "",
    recipient_code: str = "",
) -> str:
    """Формирует текст анонимной оплаты: строго БЕЗ банковских карт, номеров и личных имён."""
    title = tier_info["title"]
    stars = tier_info["stars"]
    price_kgs = tier_info["price_kgs"]

    if is_gift:
        header = (
            f"<b>Анонимная оплата подарка: {title} ({stars} ⭐ / {price_kgs} сом)</b>\n"
            f"• <b>Получатель:</b> {html.escape(recipient_name)} (<code>{html.escape(recipient_code)}</code>)\n"
        )
    else:
        header = f"<b>Анонимная оплата: {title} ({stars} ⭐ / {price_kgs} сом)</b>\n"

    methods = []
    if settings.pay_crypto_bot_link and settings.pay_crypto_bot_link.strip():
        link = html.escape(settings.pay_crypto_bot_link.strip())
        methods.append(f"• <b>@CryptoBot (USDT / TON / BTC):</b> <a href='{link}'>{link}</a>")

    if settings.pay_tribute and settings.pay_tribute.strip():
        link = html.escape(settings.pay_tribute.strip())
        methods.append(f"• <b>Tribute:</b> <a href='{link}'>{link}</a>")

    if settings.pay_ton and settings.pay_ton.strip():
        addr = html.escape(settings.pay_ton.strip())
        methods.append(f"• <b>TON кошелёк (бренд SyncPai):</b>\n<code>{addr}</code>\n<i>(нажмите на адрес, чтобы скопировать)</i>")

    if not methods:
        body = (
            "<i>Альтернативные реквизиты сейчас не настроены. "
            "Пожалуйста, используйте мгновенную оплату в 1 тап через Telegram Stars (⭐).</i>"
        )
    else:
        body = (
            "<b>Доступные анонимные методы под брендом SyncPai:</b>\n"
            + "\n\n".join(methods)
            + "\n\n<i>После отправки перевода отправьте сюда скриншот или хеш транзакции — "
            "администратор подтвердит активацию в течение 5–30 минут.</i>"
        )

    return f"{header}\n{body}"


@router.message(Command("support"))
@router.callback_query(F.data == "show_tiers")
async def show_tiers_menu(event: Message | CallbackQuery, state: FSMContext):
    await state.clear()
    caption = (
        f"{format_goal_banner()}\n\n"
        "Выбери подходящий уровень поддержки или порадуй друга:"
    )

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="⚡ SyncPai Plus — 55 ⭐ (99 сом)", callback_data="tier_supporter")],
        [InlineKeyboardButton(text="🔥 SyncPai Pro — 110 ⭐ (199 сом)", callback_data="tier_vip")],
        [InlineKeyboardButton(text="👑 Founders Club (Навсегда) — 270 ⭐ (490 сом)", callback_data="tier_producer")],
        [InlineKeyboardButton(text="🎁 Подарить подписку другу", callback_data="gift_start")],
        [InlineKeyboardButton(text="← Назад", callback_data="cancel_action")],
    ])

    await send_or_edit_card(
        event,
        card_key="support",
        caption=caption,
        reply_markup=kb,
    )


@router.callback_query(F.data.startswith("tier_"))
async def cb_select_tier(callback: CallbackQuery, state: FSMContext):
    tier_id = (callback.data or "").removeprefix("tier_")
    info = TIERS_DATA.get(tier_id)
    if not info:
        await callback.answer("Уровень не найден", show_alert=True)
        return

    profile = supabase_client.get_profile_by_tg_id(callback.from_user.id)
    not_linked_warning = ""
    if not profile:
        not_linked_warning = (
            "\n<i>Примечание: твой профиль ещё не привязан — после или до оплаты введи "
            "<code>SP-XXXXXX</code> или <code>Ник#Тег</code> через /start.</i>\n"
        )

    perks_str = "\n".join(info["perks"])
    caption = (
        f"<b>{info['title']}</b>\n\n"
        f"• <b>Стоимость:</b> {info['stars']} Telegram Stars (или ~{info['price_kgs']} сом)\n"
        f"• <b>Срок действия:</b> {info['days_label']}\n\n"
        f"<b>Что входит:</b>\n{perks_str}\n"
        f"{not_linked_warning}\n"
        f"Мгновенная активация в 1 тап:"
    )

    buttons = [
        [InlineKeyboardButton(text=f"⭐ Оплатить {info['stars']} Stars (Мгновенно)", callback_data=f"pay_stars_{tier_id}")],
    ]
    if has_anonymous_alternatives():
        buttons.append([
            InlineKeyboardButton(text="💎 Альтернативные способы (Crypto / TON / Tribute)", callback_data=f"pay_manual_{tier_id}")
        ])
    buttons.append([
        InlineKeyboardButton(text="🎁 Подарить этот тариф другу", callback_data=f"gift_tier_direct_{tier_id}")
    ])
    buttons.append([
        InlineKeyboardButton(text="← Назад к тарифам", callback_data="show_tiers")
    ])

    kb = InlineKeyboardMarkup(inline_keyboard=buttons)

    await send_or_edit_card(
        callback,
        card_key="support",
        caption=caption,
        reply_markup=kb,
    )


# --------------------------------------------------------------------------
# СЦЕНАРИЙ: «ПОДАРИТЬ ПОДПИСКУ ДРУГУ»
# --------------------------------------------------------------------------

@router.callback_query(F.data == "gift_start")
async def cb_gift_start(callback: CallbackQuery, state: FSMContext):
    await state.set_state(GiftStates.waiting_for_friend_code)
    caption = (
        "<b>🎁 Подарить подписку другу</b>\n\n"
        "Порадуй друга анимированными рамками аватара, кастомным титулом и расширенными комнатами!\n\n"
        "Отправь в чат <b>Код дружбы</b> получателя (например, <code>SP-XXXXXX</code>) "
        "или его <b>@username</b> в Telegram:"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="← Назад к тарифам", callback_data="show_tiers")],
    ])
    await send_or_edit_card(
        callback,
        card_key="support",
        caption=caption,
        reply_markup=kb,
    )


@router.callback_query(F.data.startswith("gift_tier_direct_"))
async def cb_gift_tier_direct(callback: CallbackQuery, state: FSMContext):
    tier_id = (callback.data or "").removeprefix("gift_tier_direct_")
    await state.set_state(GiftStates.waiting_for_friend_code)
    await state.update_data(gift_preselected_tier=tier_id)

    caption = (
        "<b>🎁 Подарить подписку другу</b>\n\n"
        f"Выбран тариф: <b>{TIERS_DATA.get(tier_id, {}).get('title', 'SyncPai')}</b>\n\n"
        "Отправь в чат <b>Код дружбы</b> получателя (например, <code>SP-XXXXXX</code>) "
        "или его <b>@username</b> в Telegram:"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="← Назад к тарифам", callback_data="show_tiers")],
    ])
    await send_or_edit_card(
        callback,
        card_key="support",
        caption=caption,
        reply_markup=kb,
    )


@router.message(GiftStates.waiting_for_friend_code, F.text)
async def process_gift_recipient_input(message: Message, state: FSMContext):
    raw = (message.text or "").strip()
    if raw.startswith("/"):
        await state.clear()
        return

    profile = supabase_client.get_profile_by_code_or_tag(raw)
    if not profile:
        await message.answer(
            "❌ <b>Пользователь не найден</b>\n\n"
            "Проверь правильность кода дружбы (<code>SP-XXXXXX</code>) "
            "или @username в Telegram и попробуй ещё раз.\n\n"
            "<i>Друг может посмотреть свой код в приложении SyncPai во вкладке «Профиль».</i>",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="← Назад к тарифам", callback_data="show_tiers")],
            ]),
        )
        return

    uname = html.escape(str(profile.get("username") or "Пользователь"))
    raw_tag = str(profile.get("tag") or "")
    tag = html.escape(f"#{raw_tag.lstrip('#')}" if raw_tag else "")
    friend_code = html.escape(str(profile.get("friend_code") or "—"))
    recipient_display = f"{uname}{tag}"

    fsm_data = await state.get_data()
    preselected = fsm_data.get("gift_preselected_tier")

    await state.update_data(
        gift_recipient_id=profile["id"],
        gift_recipient_name=recipient_display,
        gift_recipient_code=friend_code,
        gift_recipient_tg_id=profile.get("telegram_id"),
    )

    if preselected and preselected in TIERS_DATA:
        await _show_gift_tier_details(message, state, preselected)
        return

    caption = (
        f"<b>🎁 Получатель подарка: {recipient_display}</b>\n"
        f"• Код дружбы: <code>{friend_code}</code>\n\n"
        f"Выбери уровень подписки, который хочешь подарить:"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="⚡ Plus — 55 ⭐ (99 сом)", callback_data="gift_tier_supporter")],
        [InlineKeyboardButton(text="🔥 Pro — 110 ⭐ (199 сом)", callback_data="gift_tier_vip")],
        [InlineKeyboardButton(text="👑 Founders (Навсегда) — 270 ⭐ (490 сом)", callback_data="gift_tier_producer")],
        [InlineKeyboardButton(text="🔍 Выбрать другого друга", callback_data="gift_start")],
        [InlineKeyboardButton(text="← Отмена", callback_data="show_tiers")],
    ])

    await message.answer(
        caption,
        parse_mode="HTML",
        reply_markup=kb,
    )


async def _show_gift_tier_details(event: Message | CallbackQuery, state: FSMContext, tier_id: str):
    info = TIERS_DATA.get(tier_id)
    if not info:
        return

    data = await state.get_data()
    recipient_name = data.get("gift_recipient_name") or "Друг"
    recipient_code = data.get("gift_recipient_code") or "—"

    await state.update_data(gift_selected_tier=tier_id)

    perks_str = "\n".join(info["perks"])
    caption = (
        f"<b>🎁 Подарок для {recipient_name}</b> (<code>{recipient_code}</code>)\n\n"
        f"<b>Тариф:</b> {info['title']}\n"
        f"• <b>Стоимость:</b> {info['stars']} Telegram Stars (или ~{info['price_kgs']} сом)\n"
        f"• <b>Срок действия:</b> {info['days_label']}\n\n"
        f"<b>Что получит друг:</b>\n{perks_str}\n\n"
        f"Мгновенная отправка в 1 тап:"
    )
    buttons = [
        [InlineKeyboardButton(text=f"⭐ Оплатить {info['stars']} Stars (Мгновенно)", callback_data=f"gift_pay_stars_{tier_id}")],
    ]
    if has_anonymous_alternatives():
        buttons.append([
            InlineKeyboardButton(text="💎 Альтернативные способы (Crypto / TON / Tribute)", callback_data=f"gift_pay_manual_{tier_id}")
        ])
    buttons.append([
        InlineKeyboardButton(text="← Выбрать другой тариф", callback_data="gift_back_to_recipient")
    ])

    kb = InlineKeyboardMarkup(inline_keyboard=buttons)

    if isinstance(event, CallbackQuery):
        await send_or_edit_card(
            event,
            card_key="support",
            caption=caption,
            reply_markup=kb,
        )
    else:
        await event.answer(
            caption,
            parse_mode="HTML",
            reply_markup=kb,
        )


@router.callback_query(F.data.startswith("gift_tier_"))
async def cb_gift_tier_selected(callback: CallbackQuery, state: FSMContext):
    tier_id = (callback.data or "").removeprefix("gift_tier_")
    await _show_gift_tier_details(callback, state, tier_id)


@router.callback_query(F.data == "gift_back_to_recipient")
async def cb_gift_back_to_recipient(callback: CallbackQuery, state: FSMContext):
    data = await state.get_data()
    recipient_display = data.get("gift_recipient_name") or "Друг"
    friend_code = data.get("gift_recipient_code") or "—"

    caption = (
        f"<b>🎁 Получатель подарка: {recipient_display}</b>\n"
        f"• Код дружбы: <code>{friend_code}</code>\n\n"
        f"Выбери уровень подписки, который хочешь подарить:"
    )
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="⚡ Plus — 55 ⭐ (99 сом)", callback_data="gift_tier_supporter")],
        [InlineKeyboardButton(text="🔥 Pro — 110 ⭐ (199 сом)", callback_data="gift_tier_vip")],
        [InlineKeyboardButton(text="👑 Founders (Навсегда) — 270 ⭐ (490 сом)", callback_data="gift_tier_producer")],
        [InlineKeyboardButton(text="🔍 Выбрать другого друга", callback_data="gift_start")],
        [InlineKeyboardButton(text="← Отмена", callback_data="show_tiers")],
    ])
    await send_or_edit_card(
        callback,
        card_key="support",
        caption=caption,
        reply_markup=kb,
    )


# --------------------------------------------------------------------------
# ОПЛАТА ЧЕРЕЗ TELEGRAM STARS (0-СЕКУНДНАЯ АВТО-АКТИВАЦИЯ)
# --------------------------------------------------------------------------

@router.callback_query(F.data.startswith("pay_stars_"))
async def cb_pay_stars(callback: CallbackQuery):
    tier_id = (callback.data or "").removeprefix("pay_stars_")
    info = TIERS_DATA.get(tier_id)
    if not info:
        await callback.answer("Ошибка уровня", show_alert=True)
        return

    prices = [LabeledPrice(label=info["title"], amount=info["stars"])]

    await callback.message.answer_invoice(
        title=f"Подписка {info['title']}",
        description=f"Мгновенная активация {info['title']} в SyncPai ({info['days_label']})",
        payload=f"syncpai_tier_{tier_id}",
        currency="XTR",
        prices=prices,
        provider_token="",
    )
    await callback.answer()


@router.callback_query(F.data.startswith("gift_pay_stars_"))
async def cb_gift_pay_stars(callback: CallbackQuery, state: FSMContext):
    tier_id = (callback.data or "").removeprefix("gift_pay_stars_")
    info = TIERS_DATA.get(tier_id)
    if not info:
        await callback.answer("Ошибка уровня", show_alert=True)
        return

    data = await state.get_data()
    recipient_id = data.get("gift_recipient_id")
    recipient_name = data.get("gift_recipient_name") or "Друг"
    if not recipient_id:
        await callback.answer("Получатель подарка не выбран", show_alert=True)
        return

    prices = [LabeledPrice(label=f"Подарок: {info['title']}", amount=info["stars"])]

    await callback.message.answer_invoice(
        title=f"Подарок {info['title']} для {recipient_name}",
        description=f"Мгновенная подарочная подписка {info['title']} в SyncPai ({info['days_label']}) для {recipient_name}",
        payload=f"syncpai_gift_{tier_id}_{recipient_id}",
        currency="XTR",
        prices=prices,
        provider_token="",
    )
    await callback.answer()


@router.pre_checkout_query()
async def process_pre_checkout(pre_checkout_query: PreCheckoutQuery):
    await pre_checkout_query.answer(ok=True)


@router.message(F.successful_payment)
async def process_successful_payment(message: Message):
    """0-секундная авто-активация подписки через Telegram Stars."""
    payload = message.successful_payment.invoice_payload

    # 1. Подарочный платёж: syncpai_gift_{tier_id}_{recipient_id}
    if payload.startswith("syncpai_gift_"):
        parts = payload.removeprefix("syncpai_gift_").split("_", 1)
        if len(parts) >= 2:
            tier_id, recipient_id = parts[0], parts[1]
            info = TIERS_DATA.get(tier_id, TIERS_DATA["supporter"])
            supabase_client.set_supporter_tier(recipient_id, tier_id, days=info["days"])

            recip = supabase_client.get_profile_by_code_or_tag(recipient_id)
            recip_name = html.escape(str(recip.get("username") or "Друг")) if recip else "Друг"
            recip_tg_id = recip.get("telegram_id") if recip else None

            await message.answer(
                f"🎁 <b>Подарок успешно отправлен!</b>\n\n"
                f"Подписка <b>{info['title']}</b> мгновенно активирована в профиле <b>{recip_name}</b> ({info['days_label']})!\n"
                f"Спасибо за поддержку проекта SyncPai!",
                parse_mode="HTML",
            )

            # Личное уведомление получателю, если его Telegram привязан
            if recip_tg_id:
                sender_name = html.escape(message.from_user.full_name or message.from_user.username or "Друг")
                try:
                    await message.bot.send_message(
                        chat_id=recip_tg_id,
                        text=(
                            f"🎁 <b>Вам подарок!</b>\n\n"
                            f"Пользователь <b>{sender_name}</b> подарил вам подписку <b>SyncPai {info['title']}</b>!\n\n"
                            f"Все возможности тарифа уже активированы в вашем профиле SyncPai. "
                            f"Перезапустите приложение, чтобы наслаждаться новыми возможностями!"
                        ),
                        parse_mode="HTML",
                    )
                except Exception as e:
                    logger.warning(f"Failed to DM gift recipient {recip_tg_id}: {e}")
        return

    # 2. Платёж для своего аккаунта: syncpai_tier_{tier_id}
    tier_id = payload.removeprefix("syncpai_tier_")
    info = TIERS_DATA.get(tier_id, TIERS_DATA["supporter"])

    profile = supabase_client.get_profile_by_tg_id(message.from_user.id)
    if profile:
        supabase_client.set_supporter_tier(profile["id"], tier_id, days=info["days"])
        uname = html.escape(str(profile.get("username") or "Пользователь"))
        await message.answer(
            f"✨ <b>Подписка {info['title']} успешно активирована!</b>\n\n"
            f"Все бонусы тарифа начислены для аккаунта <b>{uname}</b> ({info['days_label']}).\n"
            f"Перезапусти приложение SyncPai, чтобы увидеть обновлённый статус.",
            parse_mode="HTML",
        )
    else:
        await message.answer(
            f"⭐ <b>Оплата {info['title']} прошла успешно!</b>\n\n"
            f"Привяжи профиль через /start (введи код <code>SP-XXXXXX</code> или <code>Ник#Тег</code>), "
            f"и статус активируется мгновенно.",
            parse_mode="HTML",
        )


# --------------------------------------------------------------------------
# АНОНИМНЫЕ АЛЬТЕРНАТИВНЫЕ МЕТОДЫ (CRYPTO / TON / TRIBUTE, ZERO BANK CARDS)
# --------------------------------------------------------------------------

@router.callback_query(F.data.startswith("pay_manual_"))
async def cb_pay_manual(callback: CallbackQuery, state: FSMContext):
    tier_id = (callback.data or "").removeprefix("pay_manual_")
    info = TIERS_DATA.get(tier_id)
    if not info:
        await callback.answer("Ошибка уровня", show_alert=True)
        return

    await state.update_data(selected_tier=tier_id, is_gift=False)
    await state.set_state(ReceiptUploadState.waiting_for_receipt)

    caption = _build_anonymous_payment_caption(info, is_gift=False)

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="← Отмена", callback_data="cancel_action")],
    ])

    await send_or_edit_card(
        callback,
        card_key="support",
        caption=caption,
        reply_markup=kb,
    )


@router.callback_query(F.data.startswith("gift_pay_manual_"))
async def cb_gift_pay_manual(callback: CallbackQuery, state: FSMContext):
    tier_id = (callback.data or "").removeprefix("gift_pay_manual_")
    info = TIERS_DATA.get(tier_id)
    if not info:
        await callback.answer("Ошибка уровня", show_alert=True)
        return

    data = await state.get_data()
    recipient_name = data.get("gift_recipient_name") or "Друг"
    recipient_code = data.get("gift_recipient_code") or "—"

    await state.update_data(
        selected_tier=tier_id,
        is_gift=True,
    )
    await state.set_state(ReceiptUploadState.waiting_for_receipt)

    caption = _build_anonymous_payment_caption(
        info,
        is_gift=True,
        recipient_name=recipient_name,
        recipient_code=recipient_code,
    )

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="← Отмена", callback_data="cancel_action")],
    ])

    await send_or_edit_card(
        callback,
        card_key="support",
        caption=caption,
        reply_markup=kb,
    )


@router.message(ReceiptUploadState.waiting_for_receipt, F.photo | F.document | F.text)
async def process_receipt_file(message: Message, state: FSMContext):
    data = await state.get_data()
    tier_id = data.get("selected_tier", "supporter")
    tier_info = TIERS_DATA.get(tier_id, TIERS_DATA["supporter"])
    is_gift = data.get("is_gift", False)
    recipient_id = data.get("gift_recipient_id", "")
    recipient_name = data.get("gift_recipient_name", "")
    recipient_code = data.get("gift_recipient_code", "")
    await state.clear()

    sender_tg_id = message.from_user.id
    sender_username = html.escape(message.from_user.username or "без_юзернейма")

    tx_note = ""
    if message.text:
        tx_note = f"\n• <b>Комментарий / Хеш TX:</b> <code>{html.escape(message.text.strip())}</code>"

    if is_gift:
        user_info = (
            f"• <b>ТИП: 🎁 ПОДАРОК ДРУГУ</b>\n"
            f"• От: @{sender_username} (TG ID: <code>{sender_tg_id}</code>)\n"
            f"• Получатель: <b>{recipient_name}</b> (Код: <code>{recipient_code}</code>, ID: <code>{recipient_id}</code>)\n"
            f"• Уровень: <b>{tier_info['title']}</b> ({tier_info['stars']} ⭐ / {tier_info['price_kgs']} сом){tx_note}"
        )
        admin_kb = InlineKeyboardMarkup(inline_keyboard=[
            [
                InlineKeyboardButton(
                    text="Одобрить подарок",
                    callback_data=f"admin_apprgift_{sender_tg_id}_{tier_id}_{recipient_id}",
                ),
                InlineKeyboardButton(
                    text="Отклонить",
                    callback_data=f"admin_reject_{sender_tg_id}",
                ),
            ]
        ])
    else:
        profile = supabase_client.get_profile_by_tg_id(message.from_user.id)
        profile_info_str = "Не привязан"
        profile_id = ""
        if profile:
            uname = html.escape(str(profile.get("username") or "Пользователь"))
            tag = html.escape(str(profile.get("tag") or ""))
            fcode = html.escape(str(profile.get("friend_code") or "—"))
            profile_info_str = f"{uname}{tag} (Code: <code>{fcode}</code>)"
            profile_id = profile.get("id", "")

        user_info = (
            f"• От: @{sender_username} (TG ID: <code>{sender_tg_id}</code>)\n"
            f"• Профиль SyncPai: {profile_info_str}\n"
            f"• Уровень: <b>{tier_info['title']}</b> ({tier_info['stars']} ⭐ / {tier_info['price_kgs']} сом){tx_note}"
        )
        admin_kb = InlineKeyboardMarkup(inline_keyboard=[
            [
                InlineKeyboardButton(
                    text="Одобрить",
                    callback_data=f"admin_approve_{sender_tg_id}_{tier_id}_{profile_id or 'none'}",
                ),
                InlineKeyboardButton(
                    text="Отклонить",
                    callback_data=f"admin_reject_{sender_tg_id}",
                ),
            ]
        ])

    dest_chat = settings.support_chat_id or settings.admin_telegram_id
    caption = f"<b>Новый чек/транзакция на подтверждение</b>\n\n{user_info}"
    try:
        if message.photo:
            await message.bot.send_photo(
                chat_id=dest_chat,
                photo=message.photo[-1].file_id,
                caption=caption,
                parse_mode="HTML",
                reply_markup=admin_kb,
            )
        elif message.document:
            await message.bot.send_document(
                chat_id=dest_chat,
                document=message.document.file_id,
                caption=caption,
                parse_mode="HTML",
                reply_markup=admin_kb,
            )
        elif message.text:
            await message.bot.send_message(
                chat_id=dest_chat,
                text=caption,
                parse_mode="HTML",
                reply_markup=admin_kb,
            )

        await message.answer(
            "<b>Данные отправлены на проверку</b>\n\n"
            "Обычно проверка занимает 5–30 минут. Как только платёж подтвердится, "
            "я сразу пришлю уведомление и активирую уровень.",
            parse_mode="HTML",
        )
    except Exception as e:
        await message.answer(
            f"Ошибка отправки данных администратору: {html.escape(str(e))}.",
            parse_mode="HTML",
        )
