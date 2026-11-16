import asyncio
import logging
from aiogram import Bot, Dispatcher
from aiogram.fsm.storage.memory import MemoryStorage
from aiogram.types import BotCommand
from apscheduler.schedulers.asyncio import AsyncIOScheduler

from config import settings
from handlers import start_profile, support_payments, downloads, admin
from services.expiration_worker import check_expired_supporters

logging.basicConfig(
    level=getattr(logging, settings.log_level.upper(), logging.INFO),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("syncpai_bot")


async def set_bot_commands(bot: Bot):
    commands = [
        BotCommand(command="start", description="Главное меню и привязка аккаунта"),
        BotCommand(command="profile", description="Мой профиль SyncPai"),
        BotCommand(command="support", description="Поддержать проект и подписки"),
        BotCommand(command="download", description="Скачать приложение (.apk / .exe)"),
    ]
    await bot.set_my_commands(commands)


async def main():
    logger.info("Starting SyncPai Telegram Bot...")

    bot = Bot(token=settings.bot_token)
    dp = Dispatcher(storage=MemoryStorage())

    # Регистрация модулей
    dp.include_router(start_profile.router)
    dp.include_router(support_payments.router)
    dp.include_router(downloads.router)
    dp.include_router(admin.router)

    # Настройка APScheduler для фонового воркера проверки истекших подписок
    scheduler = AsyncIOScheduler()
    scheduler.add_job(
        check_expired_supporters,
        trigger="interval",
        hours=24,
        kwargs={"bot": bot},
        id="supporter_expiration_check",
    )
    scheduler.start()
    logger.info("Background expiration scheduler started (24h interval).")

    await set_bot_commands(bot)

    try:
        await dp.start_polling(bot, allowed_updates=dp.resolve_used_update_types())
    finally:
        scheduler.shutdown()
        await bot.session.close()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        logger.info("Bot stopped.")

