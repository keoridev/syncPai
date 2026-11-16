from aiogram import Router, F
from aiogram.filters import Command
from aiogram.types import Message, CallbackQuery, InlineKeyboardMarkup, InlineKeyboardButton
from db import supabase_client

router = Router(name="downloads")


@router.message(Command("download"))
@router.callback_query(F.data == "download_app")
async def show_downloads(event: Message | CallbackQuery):
    config = supabase_client.get_latest_app_config()

    latest_version = "1.0.0"
    apk_url = ""
    exe_url = ""
    changelog = "Исправления ошибок и повышение плавности интерфейса."

    if config:
        latest_version = config.get("latest_version") or "1.0.0"
        apk_url = (config.get("android_apk_url") or "").strip()
        exe_url = (config.get("windows_exe_url") or "").strip()
        changelog = (config.get("changelog") or changelog).strip()

    text = (
        f"🚀 <b>Загрузка SyncPai v{latest_version}</b>\n\n"
        f"<b>Что нового:</b>\n"
        f"<i>{changelog}</i>\n\n"
        f"Выберите вашу платформу для скачивания:"
    )

    buttons = []
    if apk_url:
        buttons.append([InlineKeyboardButton(text="📱 Скачать для Android (.apk)", url=apk_url)])
    else:
        buttons.append([InlineKeyboardButton(text="📱 Android (.apk) — скоро", callback_data="no_download_link")])

    if exe_url:
        buttons.append([InlineKeyboardButton(text="💻 Скачать для Windows (.exe)", url=exe_url)])
    else:
        buttons.append([InlineKeyboardButton(text="💻 Windows (.exe) — скоро", callback_data="no_download_link")])

    buttons.append([InlineKeyboardButton(text="◀️ В главное меню", callback_data="cancel_action")])

    kb = InlineKeyboardMarkup(inline_keyboard=buttons)

    if isinstance(event, CallbackQuery):
        await event.message.edit_text(text, parse_mode="HTML", reply_markup=kb)
        await event.answer()
    else:
        await event.answer(text, parse_mode="HTML", reply_markup=kb)


@router.callback_query(F.data == "no_download_link")
async def cb_no_download_link(callback: CallbackQuery):
    await callback.answer("Ссылка на сборку временно недоступна или обновляется разработчиками.", show_alert=True)

