import html
from aiogram import F, Router
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from aiogram.types import CallbackQuery, InlineKeyboardButton, InlineKeyboardMarkup, Message
from db import supabase_client
from services.card_renderer import send_or_edit_card

router = Router(name="downloads")


@router.message(Command("download"))
@router.callback_query(F.data == "download_app")
async def show_downloads(event: Message | CallbackQuery, state: FSMContext):
    await state.clear()
    config = supabase_client.get_latest_app_config()

    latest_version = "1.0.0"
    apk_url = ""
    exe_url = ""
    changelog = "Исправления ошибок и повышение плавности интерфейса."

    if config:
        latest_version = html.escape(str(config.get("latest_version") or "1.0.0"))
        apk_url = (config.get("android_apk_url") or "").strip()
        exe_url = (config.get("windows_exe_url") or "").strip()
        changelog = html.escape((config.get("changelog") or changelog).strip())

    caption = (
        f"<b>Загрузка SyncPai v{latest_version}</b>\n\n"
        f"<b>Что нового:</b>\n"
        f"<i>{changelog}</i>\n\n"
        f"Выбери платформу:"
    )

    buttons = []
    if apk_url:
        buttons.append([InlineKeyboardButton(text="Скачать для Android (.apk)", url=apk_url)])
    else:
        buttons.append([InlineKeyboardButton(text="Android (.apk) — скоро", callback_data="no_download_link")])

    if exe_url:
        buttons.append([InlineKeyboardButton(text="Скачать для Windows (.exe)", url=exe_url)])
    else:
        buttons.append([InlineKeyboardButton(text="Windows (.exe) — скоро", callback_data="no_download_link")])

    buttons.append([InlineKeyboardButton(text="← Назад", callback_data="cancel_action")])

    await send_or_edit_card(
        event,
        card_key="download",
        caption=caption,
        reply_markup=InlineKeyboardMarkup(inline_keyboard=buttons),
    )


@router.callback_query(F.data == "no_download_link")
async def cb_no_download_link(callback: CallbackQuery):
    await callback.answer("Ссылка на сборку временно недоступна.", show_alert=True)
