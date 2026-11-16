from aiogram import Router, F
from aiogram.filters import Command
from aiogram.types import (
    Message,
    CallbackQuery,
    InlineKeyboardMarkup,
    InlineKeyboardButton,
    LabeledPrice,
    PreCheckoutQuery,
)
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import StatesGroup, State

from config import settings
from db import supabase_client

router = Router(name="support_payments")


class ReceiptUploadState(StatesGroup):
    waiting_for_receipt = State()
    tier_selected = State()


TIERS_DATA = {
    "supporter": {
        "title": "⚡ SyncPai Plus",
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
        "title": "✨ SyncPai Pro",
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
        "title": "👑 Founders Club",
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
async def show_tiers_menu(event: Message | CallbackQuery):
    text = (
        "💎 <b>Уровни поддержки SyncPai</b>\n\n"
        "Поддерживая проект, вы помогаете нам оплачивать серверы синхронизации, "
        "развивать плеер и выпускать обновления без рекламы!\n\n"
        "Выберите желаемый уровень:"
    )

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="⚡ Plus — 149 ₽ / 100 ⭐️", callback_data="tier_supporter")],
        [InlineKeyboardButton(text="✨ Pro — 349 ₽ / 250 ⭐️", callback_data="tier_vip")],
        [InlineKeyboardButton(text="👑 Founders Club — 990 ₽ / 700 ⭐️", callback_data="tier_producer")],
        [InlineKeyboardButton(text="◀️ В главное меню", callback_data="cancel_action")],
    ])

    if isinstance(event, CallbackQuery):
        await event.message.edit_text(text, parse_mode="HTML", reply_markup=kb)
        await event.answer()
    else:
        await event.answer(text, parse_mode="HTML", reply_markup=kb)


@router.callback_query(F.data.startswith("tier_"))
async def cb_select_tier(callback: CallbackQuery, state: FSMContext):
    tier_id = callback.data.replace("tier_", "")
    info = TIERS_DATA.get(tier_id)
    if not info:
        await callback.answer("Уровень не найден", show_alert=True)
        return

    profile = supabase_client.get_profile_by_tg_id(callback.from_user.id)
    not_linked_warning = ""
    if not profile:
        not_linked_warning = (
            "\n⚠️ <i>Внимание: ваш аккаунт SyncPai еще не привязан к боту! "
            "Перед оплатой рекомендуется выполнить /start и привязать профиль.</i>\n"
        )

    perks_str = "\n".join(info["perks"])
    text = (
        f"<b>{info['title']}</b>\n\n"
        f"💳 Стоимость: <b>{info['price_rub']} ₽</b> (или <b>{info['stars']} Telegram Stars</b>)\n"
        f"⏳ Срок действия: <b>{info['days']} дней</b>\n\n"
        f"<b>Возможности:</b>\n{perks_str}\n"
        f"{not_linked_warning}\n"
        f"Выберите удобный способ оплаты:"
    )

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=f"⭐️ Оплатить {info['stars']} Stars", callback_data=f"pay_stars_{tier_id}")],
        [InlineKeyboardButton(text="💳 Перевод / Boosty / Crypto", callback_data=f"pay_manual_{tier_id}")],
        [InlineKeyboardButton(text="◀️ Назад к тарифам", callback_data="show_tiers")],
    ])

    await callback.message.edit_text(text, parse_mode="HTML", reply_markup=kb)
    await callback.answer()


@router.callback_query(F.data.startswith("pay_stars_"))
async def cb_pay_stars(callback: CallbackQuery):
    tier_id = callback.data.replace("pay_stars_", "")
    info = TIERS_DATA.get(tier_id)
    if not info:
        await callback.answer("Ошибка уровня", show_alert=True)
        return

    prices = [LabeledPrice(label=info["title"], amount=info["stars"])]

    await callback.message.answer_invoice(
        title=f"Подписка {info['title']}",
        description=f"Активация {info['title']} в SyncPai на {info['days']} дней",
        payload=f"syncpai_tier_{tier_id}",
        currency="XTR",  # Telegram Stars
        prices=prices,
        provider_token="",  # Для Stars token пустой
    )
    await callback.answer()


@router.pre_checkout_query()
async def process_pre_checkout(pre_checkout_query: PreCheckoutQuery):
    await pre_checkout_query.answer(ok=True)


@router.message(F.successful_payment)
async def process_successful_payment(message: Message):
    payload = message.successful_payment.invoice_payload
    tier_id = payload.replace("syncpai_tier_", "")
    info = TIERS_DATA.get(tier_id, TIERS_DATA["supporter"])

    profile = supabase_client.get_profile_by_tg_id(message.from_user.id)
    if profile:
        supabase_client.set_supporter_tier(profile["id"], tier_id, days=info["days"])
        await message.answer(
            f"🎉 <b>Спасибо за поддержку!</b>\n\n"
            f"Уровень <b>{info['title']}</b> успешно активирован для аккаунта <b>{profile.get('username')}</b> на {info['days']} дней!\n"
            f"Перезапустите приложение SyncPai, чтобы увидеть новый бейдж и рамки.",
            parse_mode="HTML"
        )
    else:
        await message.answer(
            f"🎉 <b>Оплата {info['title']} прошла успешно!</b>\n\n"
            f"Но ваш аккаунт SyncPai пока не привязан. Нажмите /start и отправьте ваш <code>SP-XXXXXX</code> код дружбы, "
            f"и статус будет зачислен автоматически!",
            parse_mode="HTML"
        )


@router.callback_query(F.data.startswith("pay_manual_"))
async def cb_pay_manual(callback: CallbackQuery, state: FSMContext):
    tier_id = callback.data.replace("pay_manual_", "")
    info = TIERS_DATA.get(tier_id)
    if not info:
        await callback.answer("Ошибка уровня", show_alert=True)
        return

    await state.update_data(selected_tier=tier_id)
    await state.set_state(ReceiptUploadState.waiting_for_receipt)

    text = (
        f"💳 <b>Реквизиты для оплаты {info['title']} ({info['price_rub']} ₽)</b>\n\n"
        f"<b>1. Boosty / Банковская карта РФ:</b>\n"
        f"👉 <a href='{settings.boosty_url}'>{settings.boosty_url}</a>\n\n"
        f"<b>2. Tribute (Telegram Bot / Карты):</b>\n"
        f"👉 <a href='{settings.tribute_url}'>{settings.tribute_url}</a>\n\n"
        f"<b>3. Криптовалюта (USDT TRC20):</b>\n"
        f"<code>{settings.crypto_usdt_trc20}</code>\n\n"
        f"<b>4. TON:</b>\n"
        f"<code>{settings.crypto_ton}</code>\n\n"
        f"📸 <b>После оплаты отправьте сюда скриншот чека или квитанции!</b>\n"
        f"Администратор проверит его и моментально активирует вам уровень."
    )

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="❌ Отмена", callback_data="cancel_action")]
    ])

    await callback.message.edit_text(text, parse_mode="HTML", disable_web_page_preview=True, reply_markup=kb)
    await callback.answer()


@router.message(ReceiptUploadState.waiting_for_receipt, F.photo)
async def process_receipt_photo(message: Message, state: FSMContext):
    data = await state.get_data()
    tier_id = data.get("selected_tier", "supporter")
    tier_info = TIERS_DATA.get(tier_id, TIERS_DATA["supporter"])
    await state.clear()

    profile = supabase_client.get_profile_by_tg_id(message.from_user.id)
    profile_info_str = "⚠️ Не привязан"
    profile_id = ""
    if profile:
        profile_info_str = f"{profile.get('username')}{profile.get('tag', '')} (Code: <code>{profile.get('friend_code')}</code>)"
        profile_id = profile.get("id")

    user_info = (
        f"👤 От: @{message.from_user.username or 'без_юзернейма'} (TG ID: <code>{message.from_user.id}</code>)\n"
        f"🎮 Профиль SyncPai: {profile_info_str}\n"
        f"💎 Запрошенный уровень: <b>{tier_info['title']}</b> ({tier_info['price_rub']} ₽)"
    )

    # Клавиатура подтверждения для владельца бота
    admin_kb = InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(
                text="✅ Одобрить",
                callback_data=f"admin_approve_{message.from_user.id}_{tier_id}_{profile_id or 'none'}"
            ),
            InlineKeyboardButton(
                text="❌ Отклонить",
                callback_data=f"admin_reject_{message.from_user.id}"
            ),
        ]
    ])

    # Отправка администратору / в саппорт-чат
    dest_chat = settings.support_chat_id or settings.admin_telegram_id
    try:
        await message.bot.send_photo(
            chat_id=dest_chat,
            photo=message.photo[-1].file_id,
            caption=f"🧾 <b>Новый чек на подтверждение!</b>\n\n{user_info}",
            parse_mode="HTML",
            reply_markup=admin_kb,
        )
        await message.answer(
            "✅ <b>Чек успешно отправлен на проверку!</b>\n"
            "Обычно проверка занимает от 5 до 30 минут. Как только платёж подтвердится, "
            "вы получите уведомление и уровень активируется автоматически.",
            parse_mode="HTML"
        )
    except Exception as e:
        await message.answer(f"⚠️ Ошибка отправки чека администратору: {e}. Пожалуйста, свяжитесь с поддержкой напрямую.")

