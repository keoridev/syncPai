import logging
from aiogram import Bot
from db import supabase_client

logger = logging.getLogger(__name__)


async def check_expired_supporters(bot: Bot):
    """
    Периодический фоновый воркер (запускается через APScheduler раз в день):
    1. Находит в Supabase пользователей, у которых истёк срок supporter_until.
    2. Сбрасывает их статус на 'free'.
    3. Отправляет вежливое уведомление в Telegram с предложением продлить.
    """
    logger.info("Running daily expiration check for supporters...")
    expired_list = supabase_client.get_expired_supporters()
    if not expired_list:
        logger.info("No expired supporters found.")
        return

    logger.info(f"Found {len(expired_list)} expired supporters. Processing downgrades...")

    for row in expired_list:
        profile_id = row["id"]
        username = row.get("username", "Пользователь")
        tg_id = row.get("telegram_id")
        old_tier = row.get("supporter_tier", "supporter")

        ok = supabase_client.downgrade_to_free(profile_id)
        if ok:
            logger.info(f"Downgraded {username} ({profile_id}) to free.")
            if tg_id:
                try:
                    await bot.send_message(
                        chat_id=tg_id,
                        text=(
                            f"👋 Здравствуйте, <b>{username}</b>!\n\n"
                            f"Срок действия вашего уровня поддержки <b>{old_tier.upper()}</b> подошёл к концу.\n"
                            f"Спасибо, что были с нами и поддерживали развитие SyncPai! 💖\n\n"
                            f"Вы можете возобновить подписку в любой момент командой /support."
                        ),
                        parse_mode="HTML"
                    )
                except Exception as e:
                    logger.warning(f"Could not send expiration notification to {tg_id}: {e}")
        else:
            logger.error(f"Failed to downgrade {profile_id}")

