import html
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

router = Router(name="support_payments")


class ReceiptUploadState(StatesGroup):
    waiting_for_receipt = State()


TIERS_DATA = {
    "supporter": {
        "title": "SyncPai Plus",
        "price_rub": 149,
        "stars": 100,
        "days": 30,
        "perks": [
            "• Неоновая рамка аватара",
            "• Значок саппортера в профиле и чате комнаты",
            "• Доступ в закрытый канал бета-тестеров",
        ],
    },
    "vip": {
        "title": "SyncPai Pro",
        "price_rub": 349,
        "stars": 250,
        "days": 30,
        "perks": [
            "• Все возможности SyncPai Plus",
            "• Анимированные рамки и эксклюзивный стикер Пай-тян",
            "• Загрузка собственного GIF / арта в витрину профиля",
            "• Кастомный титул над ником и комнаты до 10 человек",
        ],
    },
    "producer": {
        "title": "Founders Club",
        "price_rub": 990,
        "stars": 700,
        "days": 90,
        "perks": [
            "• Все возможности SyncPai Pro",
            "• Упоминание в списке основателей проекта",
            "• Приоритетный запрос новой фичи или скина",
            "• Статус саппортера на 90 дней",
        ],
    },
}


@router.message(Command("support"))
@router.callback_query(F.data == "show_tiers")
async def show_tiers_menu(event: Message | CallbackQuery, state: FSMContext):
    await state.clear()
    caption = (
        "<b>Уровни поддержки SyncPai</b>\n\n"
        "Все средства идут на оплату серверов синхронизации, CDN и новых релизов без рекламы.\n\n"
        "Выбери подходящий уровень:"
    )

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="⚡ SyncPai Plus — 149 ₽ / 100 ⭐", callback_data="tier_supporter")],
        [InlineKeyboardButton(text="🔥 SyncPai Pro — 349 ₽ / 250 ⭐", callback_data="tier_vip")],
        [InlineKeyboardButton(text="👑 Founders Club — 990 ₽ / 700 ⭐", callback_data="tier_producer")],
        [InlineKeyboardButton(text="← Назад", callback_data="cancel_action")],
    ])

    await send_or_edit_card(
        event,
        card_key="support",
        caption=caption,
        reply_markup=kb,
    )


@router.callback_query(F.data.startswith("tier_"))
async def cb_select_tier(callback: CallbackQuery):
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
        f"• <b>Стоимость:</b> {info['price_rub']} ₽ (или {info['stars']} Telegram Stars)\n"
        f"• <b>Срок действия:</b> {info['days']} дней\n\n"
        f"<b>Что входит:</b>\n{perks_str}\n"
        f"{not_linked_warning}\n"
        f"Выбери способ оплаты:"
    )

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=f"⭐ Оплатить {info['stars']} Stars", callback_data=f"pay_stars_{tier_id}")],
        [InlineKeyboardButton(text="💳 Перевод / Boosty / Crypto", callback_data=f"pay_manual_{tier_id}")],
        [InlineKeyboardButton(text="← Назад к тарифам", callback_data="show_tiers")],
    ])

    await send_or_edit_card(
        callback,
        card_key="support",
        caption=caption,
        reply_markup=kb,
    )


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
        description=f"Активация {info['title']} в SyncPai на {info['days']} дней",
        payload=f"syncpai_tier_{tier_id}",
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
    payload = message.successful_payment.invoice_payload
    tier_id = payload.removeprefix("syncpai_tier_")
    info = TIERS_DATA.get(tier_id, TIERS_DATA["supporter"])

    profile = supabase_client.get_profile_by_tg_id(message.from_user.id)
    if profile:
        supabase_client.set_supporter_tier(profile["id"], tier_id, days=info["days"])
        uname = html.escape(str(profile.get("username") or "Пользователь"))
        await message.answer(
            f"<b>Спасибо за поддержку!</b>\n\n"
            f"Уровень <b>{info['title']}</b> активирован для аккаунта <b>{uname}</b> на {info['days']} дней.\n"
            f"Перезапусти приложение SyncPai, чтобы увидеть обновлённый статус.",
            parse_mode="HTML",
        )
    else:
        await message.answer(
            f"<b>Оплата {info['title']} прошла успешно</b>\n\n"
            f"Привяжи профиль через /start (по коду <code>SP-XXXXXX</code> или <code>Ник#Тег</code>), "
            f"и я начислю статус.",
            parse_mode="HTML",
        )


@router.callback_query(F.data.startswith("pay_manual_"))
async def cb_pay_manual(callback: CallbackQuery, state: FSMContext):
    tier_id = (callback.data or "").removeprefix("pay_manual_")
    info = TIERS_DATA.get(tier_id)
    if not info:
        await callback.answer("Ошибка уровня", show_alert=True)
        return

    await state.update_data(selected_tier=tier_id)
    await state.set_state(ReceiptUploadState.waiting_for_receipt)

    caption = (
        f"<b>Реквизиты для оплаты {info['title']} ({info['price_rub']} ₽)</b>\n\n"
        f"• <b>Boosty / Карта РФ:</b> <a href='{html.escape(settings.boosty_url)}'>{html.escape(settings.boosty_url)}</a>\n"
        f"• <b>Tribute:</b> <a href='{html.escape(settings.tribute_url)}'>{html.escape(settings.tribute_url)}</a>\n"
        f"• <b>USDT (TRC-20):</b> <code>{html.escape(settings.crypto_usdt_trc20)}</code>\n"
        f"• <b>TON:</b> <code>{html.escape(settings.crypto_ton)}</code>\n\n"
        f"После перевода отправь сюда скриншот или PDF-файл чека — администратор проверит его и активирует статус."
    )

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="Отмена", callback_data="cancel_action")],
    ])

    await send_or_edit_card(
        callback,
        card_key="support",
        caption=caption,
        reply_markup=kb,
    )


@router.message(ReceiptUploadState.waiting_for_receipt, F.photo | F.document)
async def process_receipt_file(message: Message, state: FSMContext):
    data = await state.get_data()
    tier_id = data.get("selected_tier", "supporter")
    tier_info = TIERS_DATA.get(tier_id, TIERS_DATA["supporter"])
    await state.clear()

    profile = supabase_client.get_profile_by_tg_id(message.from_user.id)
    profile_info_str = "Не привязан"
    profile_id = ""
    if profile:
        uname = html.escape(str(profile.get("username") or "Пользователь"))
        tag = html.escape(str(profile.get("tag") or ""))
        fcode = html.escape(str(profile.get("friend_code") or "—"))
        profile_info_str = f"{uname}{tag} (Code: <code>{fcode}</code>)"
        profile_id = profile.get("id", "")

    tg_username = html.escape(message.from_user.username or "без_юзернейма")
    user_info = (
        f"• От: @{tg_username} (TG ID: <code>{message.from_user.id}</code>)\n"
        f"• Профиль SyncPai: {profile_info_str}\n"
        f"• Уровень: <b>{tier_info['title']}</b> ({tier_info['price_rub']} ₽)"
    )

    admin_kb = InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(
                text="Одобрить",
                callback_data=f"admin_approve_{message.from_user.id}_{tier_id}_{profile_id or 'none'}",
            ),
            InlineKeyboardButton(
                text="Отклонить",
                callback_data=f"admin_reject_{message.from_user.id}",
            ),
        ]
    ])

    dest_chat = settings.support_chat_id or settings.admin_telegram_id
    caption = f"<b>Новый чек на подтверждение</b>\n\n{user_info}"
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

        await message.answer(
            "<b>Чек отправлен на проверку</b>\n\n"
            "Обычно проверка занимает 5–30 минут. Как только платёж подтвердится, "
            "я сразу пришлю уведомление и активирую уровень.",
            parse_mode="HTML",
        )
    except Exception as e:
        await message.answer(
            f"Ошибка отправки чека администратору: {html.escape(str(e))}.",
            parse_mode="HTML",
        )
