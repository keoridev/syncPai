import logging
import os
from datetime import datetime, timedelta, timezone

from aiogram import Bot, F, Router
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
from db.supabase_client import supabase

logger = logging.getLogger(__name__)
router = Router(name="feature_requests")

STARS_PRICE_XTR = int(os.getenv("STARS_PRICE_XTR", "500"))
PAYMENT_QR_DETAILS = os.getenv(
    "PAYMENT_QR_DETAILS",
    "МБанк / СБП: свяжитесь с поддержкой или прикрепите чек",
)


def _get_admin_chat_id() -> int | None:
    if settings.admin_telegram_id:
        return settings.admin_telegram_id
    for part in settings.admin_ids.split(","):
        clean = part.strip()
        if clean.isdigit():
            return int(clean)
    return None


def _is_admin(tg_user_id: int) -> bool:
    admin_id = _get_admin_chat_id()
    if admin_id is not None and tg_user_id == admin_id:
        return True
    allowed = {
        int(p.strip())
        for p in settings.admin_ids.split(",")
        if p.strip().isdigit()
    }
    return tg_user_id in allowed


class FeatureRequestStates(StatesGroup):
    waiting_for_title = State()
    waiting_for_description = State()
    waiting_for_payment = State()
    waiting_for_receipt = State()


def _admin_keyboard(req_id: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(
                    text="Принять в работу (7 дней)",
                    callback_data=f"feat_approve:{req_id}",
                ),
            ],
            [
                InlineKeyboardButton(
                    text="Фича готова!",
                    callback_data=f"feat_done:{req_id}",
                ),
                InlineKeyboardButton(
                    text="Отклонить (Возврат)",
                    callback_data=f"feat_decline:{req_id}",
                ),
            ],
        ]
    )


async def _send_to_admin(
    bot: Bot,
    req: dict,
    syncpai_nick: str,
) -> None:
    admin_chat_id = _get_admin_chat_id()
    if admin_chat_id is None:
        logger.warning("ADMIN_TELEGRAM_ID / ADMIN_IDS not configured; skipping admin alert.")
        return

    tg_user = (
        f"@{req['telegram_username']}"
        if req.get("telegram_username")
        else f"id:{req.get('telegram_user_id')}"
    )
    text = (
        f"<b>Новая заявка Priority Feature Pass</b>\n"
        f"<b>SyncPai:</b> {syncpai_nick}\n"
        f"<b>User ID:</b> <code>{req['user_id']}</code>\n"
        f"<b>Telegram:</b> {tg_user}\n"
        f"<b>Название:</b> {req['title']}\n"
        f"<b>Описание:</b> {req['description']}\n"
        f"<b>Оплата:</b> {req.get('payment_method', 'pending')} ({req.get('payment_status', 'pending')})"
    )
    await bot.send_message(
        chat_id=admin_chat_id,
        text=text,
        parse_mode="HTML",
        reply_markup=_admin_keyboard(req["id"]),
    )


async def start_feature_flow(
    message: Message,
    state: FSMContext,
    user_id: str,
) -> None:
    if not user_id:
        await message.answer("Некорректная ссылка привязки профиля.")
        return

    syncpai_nick = "Пользователь SyncPai"
    try:
        profile_res = (
            supabase.table("profiles")
            .select("id, username, display_name")
            .eq("id", user_id)
            .limit(1)
            .execute()
        )
        rows = profile_res.data or []
        if rows:
            syncpai_nick = (
                rows[0].get("display_name")
                or rows[0].get("username")
                or syncpai_nick
            )
    except Exception as e:
        logger.warning(f"Failed to load profile {user_id}: {e}")

    await state.clear()
    await state.update_data(user_id=user_id, syncpai_nick=syncpai_nick)
    await state.set_state(FeatureRequestStates.waiting_for_title)

    await message.answer(
        f"Привет, {syncpai_nick}!\n\n"
        "<b>Priority Feature Pass — Своя фича за 7 дней</b>\n"
        "1. Опишите желаемую функцию или улучшение UI.\n"
        "2. Выберите способ оплаты (Telegram Stars или QR/перевод).\n"
        "3. После проверки мы реализуем её за 7 дней (или вернём 100% оплаты) и выдадим статус <b>SyncPai Sponsor</b>.\n\n"
        "Введите короткое название фичи (до 80 символов):",
        parse_mode="HTML",
    )


async def handle_duo_invite(
    message: Message,
    state: FSMContext,
    invite_code: str,
) -> None:
    await state.clear()
    if not invite_code:
        await message.answer("Некорректный код приглашения Парного профиля.")
        return
    await message.answer(
        "<b>Приглашение в Парный профиль SyncPai</b>\n\n"
        f"Код приглашения: <code>{invite_code}</code>\n\n"
        "1. Откройте приложение SyncPai.\n"
        "2. Перейдите в <b>Профиль -> Парный профиль</b>.\n"
        "3. Введите код или откройте ссылку:\n"
        f"<code>syncpai://duo/{invite_code}</code>",
        parse_mode="HTML",
    )


@router.callback_query(F.data == "menu:order_feature")
async def menu_order_feature(callback: CallbackQuery) -> None:
    await callback.message.answer(
        "<b>Заказать фичу (7 дней)</b>\n\n"
        "Чтобы привязать заявку к вашему аккаунту SyncPai:\n"
        "1. Откройте <b>Профиль -> Поддержать -> Заказать фичу в Telegram</b>.\n"
        "2. Либо нажмите <b>«Скопировать код заявки»</b> в приложении и отправьте команду вида <code>/start feat_...</code> сюда.",
        parse_mode="HTML",
    )
    await callback.answer()


@router.callback_query(F.data == "menu:sponsor")
async def menu_sponsor(callback: CallbackQuery) -> None:
    await callback.message.answer(
        "<b>SyncPai Sponsor</b>\n\n"
        "Открывает кастомные цвета профиля, анимированные рамки, живые фоны, двойную витрину и статус спонсора.\n"
        "Оформить можно прямо в приложении SyncPai (раздел <b>Поддержать</b>) или вместе с заявкой Priority Feature Pass.",
        parse_mode="HTML",
    )
    await callback.answer()


@router.callback_query(F.data == "menu:my_requests")
async def menu_my_requests(callback: CallbackQuery) -> None:
    res = (
        supabase.table("feature_requests")
        .select("title, implementation_status, payment_status")
        .eq("telegram_user_id", callback.from_user.id)
        .order("created_at", desc=True)
        .limit(5)
        .execute()
    )
    rows = res.data or []
    if not rows:
        await callback.message.answer(
            "У вас пока нет активных заявок в Priority Feature Pass."
        )
        await callback.answer()
        return

    lines = ["<b>Ваши последние заявки:</b>"]
    for row in rows:
        lines.append(
            f"• <b>{row.get('title', 'Без названия')}</b> — статус: {row.get('implementation_status', 'review')} (оплата: {row.get('payment_status', 'pending')})"
        )
    await callback.message.answer("\n".join(lines), parse_mode="HTML")
    await callback.answer()


@router.message(FeatureRequestStates.waiting_for_title)
async def process_title(message: Message, state: FSMContext) -> None:
    title = (message.text or "").strip()
    if not title or len(title) > 80:
        await message.answer(
            "Название должно быть не длиннее 80 символов. Попробуйте ещё раз:"
        )
        return
    await state.update_data(title=title)
    await state.set_state(FeatureRequestStates.waiting_for_description)
    await message.answer("Отлично! Теперь подробно опишите, как должна работать фича:")


@router.message(FeatureRequestStates.waiting_for_description)
async def process_description(message: Message, state: FSMContext) -> None:
    desc = (message.text or message.caption or "").strip()
    if len(desc) < 10:
        await message.answer("Опишите идею чуть подробнее (минимум 10 символов):")
        return
    await state.update_data(description=desc)
    await state.set_state(FeatureRequestStates.waiting_for_payment)

    kb = InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(
                    text=f"Оплатить Telegram Stars ({STARS_PRICE_XTR} XTR)",
                    callback_data="feat_pay:stars",
                )
            ],
            [
                InlineKeyboardButton(
                    text="Оплата по QR / Переводом",
                    callback_data="feat_pay:qr",
                )
            ],
        ]
    )
    await message.answer("Выберите удобный способ оплаты:", reply_markup=kb)


@router.callback_query(
    FeatureRequestStates.waiting_for_payment, F.data == "feat_pay:stars"
)
async def pay_stars(callback: CallbackQuery, state: FSMContext) -> None:
    data = await state.get_data()
    inserted = (
        supabase.table("feature_requests")
        .insert(
            {
                "user_id": data["user_id"],
                "telegram_user_id": callback.from_user.id,
                "telegram_username": callback.from_user.username,
                "title": data["title"],
                "description": data["description"],
                "payment_method": "telegram_stars",
                "payment_status": "pending",
                "implementation_status": "review",
            }
        )
        .execute()
    )
    req_id = inserted.data[0]["id"]
    await state.update_data(req_id=req_id)

    await callback.message.answer_invoice(
        title=f"SyncPai Feature Pass: {data['title']}",
        description="Своя фича за 7 дней + SyncPai Sponsor",
        payload=f"feat_req:{req_id}",
        currency="XTR",
        prices=[LabeledPrice(label="Priority Feature Pass", amount=STARS_PRICE_XTR)],
    )
    await callback.answer()


@router.pre_checkout_query(F.invoice_payload.startswith("feat_req:"))
async def on_pre_checkout_feature(pre_checkout: PreCheckoutQuery) -> None:
    await pre_checkout.answer(ok=True)


@router.message(F.successful_payment.invoice_payload.startswith("feat_req:"))
async def on_successful_payment_feature(
    message: Message, state: FSMContext, bot: Bot
) -> None:
    payload = message.successful_payment.invoice_payload
    req_id = payload.removeprefix("feat_req:")
    updated = (
        supabase.table("feature_requests")
        .update({"payment_status": "paid"})
        .eq("id", req_id)
        .execute()
    )
    data = await state.get_data()
    if updated.data:
        await _send_to_admin(
            bot, updated.data[0], data.get("syncpai_nick", "Пользователь")
        )
    await state.clear()
    await message.answer(
        "Оплата Telegram Stars получена! Заявка отправлена на проверку, статус отображается в SyncPai -> «Мои заявки»."
    )


@router.callback_query(
    FeatureRequestStates.waiting_for_payment, F.data == "feat_pay:qr"
)
async def pay_qr(callback: CallbackQuery, state: FSMContext) -> None:
    await state.set_state(FeatureRequestStates.waiting_for_receipt)
    kb = InlineKeyboardMarkup(
        inline_keyboard=[
            [InlineKeyboardButton(text="Я оплатил", callback_data="feat_qr:paid")]
        ]
    )
    await callback.message.answer(
        f"Реквизиты для перевода:\n<code>{PAYMENT_QR_DETAILS}</code>\n\n"
        "Отправьте скриншот чека в этот чат или нажмите «Я оплатил».",
        parse_mode="HTML",
        reply_markup=kb,
    )
    await callback.answer()


@router.callback_query(
    FeatureRequestStates.waiting_for_receipt, F.data == "feat_qr:paid"
)
async def qr_paid_btn(
    callback: CallbackQuery, state: FSMContext, bot: Bot
) -> None:
    data = await state.get_data()
    inserted = (
        supabase.table("feature_requests")
        .insert(
            {
                "user_id": data["user_id"],
                "telegram_user_id": callback.from_user.id,
                "telegram_username": callback.from_user.username,
                "title": data["title"],
                "description": data["description"],
                "payment_method": "transfer_qr",
                "payment_status": "pending",
                "implementation_status": "review",
            }
        )
        .execute()
    )
    if inserted.data:
        await _send_to_admin(
            bot, inserted.data[0], data.get("syncpai_nick", "Пользователь")
        )
    await state.clear()
    await callback.message.answer(
        "Заявка отправлена на проверку! После подтверждения перевода мы начнём разработку."
    )
    await callback.answer()


@router.message(FeatureRequestStates.waiting_for_receipt, F.photo)
async def qr_receipt_photo(
    message: Message, state: FSMContext, bot: Bot
) -> None:
    data = await state.get_data()
    inserted = (
        supabase.table("feature_requests")
        .insert(
            {
                "user_id": data["user_id"],
                "telegram_user_id": message.from_user.id,
                "telegram_username": message.from_user.username,
                "title": data["title"],
                "description": data["description"],
                "payment_method": "transfer_qr",
                "payment_status": "pending",
                "implementation_status": "review",
            }
        )
        .execute()
    )
    if inserted.data:
        await _send_to_admin(
            bot, inserted.data[0], data.get("syncpai_nick", "Пользователь")
        )
        admin_chat_id = _get_admin_chat_id()
        if admin_chat_id is not None:
            await bot.forward_message(
                admin_chat_id, message.chat.id, message.message_id
            )
    await state.clear()
    await message.answer(
        "Чек получен и передан администратору! Статус обновится в SyncPai."
    )


@router.callback_query(F.data.startswith("feat_approve:"))
async def admin_approve(callback: CallbackQuery, bot: Bot) -> None:
    if not _is_admin(callback.from_user.id):
        await callback.answer("Недостаточно прав", show_alert=True)
        return
    req_id = callback.data.split(":", 1)[1]
    deadline = (datetime.now(timezone.utc) + timedelta(days=7)).isoformat()
    res = (
        supabase.table("feature_requests")
        .update(
            {
                "payment_status": "paid",
                "implementation_status": "in_progress",
                "deadline_at": deadline,
            }
        )
        .eq("id", req_id)
        .execute()
    )
    if res.data:
        req = res.data[0]
        supabase.table("profiles").update(
            {
                "tier": "sponsor",
                "sponsor_until": (
                    datetime.now(timezone.utc) + timedelta(days=365)
                ).isoformat(),
            }
        ).eq("id", req["user_id"]).execute()
        if req.get("telegram_user_id"):
            await bot.send_message(
                req["telegram_user_id"],
                f"Ваша фича «{req['title']}» принята в работу (срок до 7 дней)! Вам активирован статус SyncPai Sponsor.",
            )
    await callback.answer("Принято в работу")


@router.callback_query(F.data.startswith("feat_decline:"))
async def admin_decline(callback: CallbackQuery, bot: Bot) -> None:
    if not _is_admin(callback.from_user.id):
        await callback.answer("Недостаточно прав", show_alert=True)
        return
    req_id = callback.data.split(":", 1)[1]
    res = (
        supabase.table("feature_requests")
        .update(
            {
                "payment_status": "refunded",
                "implementation_status": "declined",
            }
        )
        .eq("id", req_id)
        .execute()
    )
    if res.data and res.data[0].get("telegram_user_id"):
        req = res.data[0]
        await bot.send_message(
            req["telegram_user_id"],
            f"Заявка «{req['title']}» отклонена по техническим причинам. Оформлен 100% возврат средств.",
        )
    await callback.answer("Отклонено с возвратом")


@router.callback_query(F.data.startswith("feat_done:"))
async def admin_done(callback: CallbackQuery, bot: Bot) -> None:
    if not _is_admin(callback.from_user.id):
        await callback.answer("Недостаточно прав", show_alert=True)
        return
    req_id = callback.data.split(":", 1)[1]
    res = (
        supabase.table("feature_requests")
        .update({"implementation_status": "completed"})
        .eq("id", req_id)
        .execute()
    )
    if res.data and res.data[0].get("telegram_user_id"):
        req = res.data[0]
        await bot.send_message(
            req["telegram_user_id"],
            f"Фича «{req['title']}» готова и войдёт в ближайшее обновление SyncPai!",
        )
    await callback.answer("Отмечено как готовое")

