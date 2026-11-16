from __future__ import annotations

import logging
from pathlib import Path
from typing import Dict, Optional

from aiogram.types import CallbackQuery, FSInputFile, InlineKeyboardMarkup, InputMediaPhoto, Message
from PIL import Image, ImageDraw, ImageFont

logger = logging.getLogger(__name__)

_ASSETS_DIR = Path(__file__).resolve().parent.parent / "assets"
_RENDERED_DIR = _ASSETS_DIR / "rendered"

_CARD_SPECS: Dict[str, Dict[str, str]] = {
    "welcome": {
        "sticker": "pai_love.png",
        "eyebrow": "SYNCPAI",
        "title": "Смотрим аниме вместе",
        "subtitle": "Синхронный плеер, общие комнаты и профиль — без рекламы",
        "accent": "#22D3EE",
    },
    "support": {
        "sticker": "pai_hype.png",
        "eyebrow": "ПОДДЕРЖКА SYNCPAI",
        "title": "Plus, Pro & Founders",
        "subtitle": "Рамки профиля, кастомные арты и помощь в оплате серверов",
        "accent": "#A855F7",
    },
    "link": {
        "sticker": "pai_laugh.png",
        "eyebrow": "ПРИВЯЗКА ПРОФИЛЯ",
        "title": "Подключите аккаунт",
        "subtitle": "Введите код дружбы SP-XXXXXX или Ник#Тег из приложения",
        "accent": "#22D3EE",
    },
    "download": {
        "sticker": "pai_hype.png",
        "eyebrow": "РЕЛИЗЫ SYNCPAI",
        "title": "Windows & Android",
        "subtitle": "Актуальные сборки приложения и список изменений",
        "accent": "#38BDF8",
    },
}

_FILE_ID_CACHE: Dict[str, str] = {}


def _load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = (
        [
            r"C:\Windows\Fonts\segoeuib.ttf",
            r"C:\Windows\Fonts\arialbd.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        ]
        if bold
        else [
            r"C:\Windows\Fonts\segoeui.ttf",
            r"C:\Windows\Fonts\arial.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        ]
    )
    for path in candidates:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size=size)
            except Exception:
                continue
    return ImageFont.load_default()


def _hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    cleaned = hex_color.lstrip("#")
    return (int(cleaned[0:2], 16), int(cleaned[2:4], 16), int(cleaned[4:6], 16))


def _wrap_text(
    draw: ImageDraw.ImageDraw,
    text: str,
    font: ImageFont.FreeTypeFont | ImageFont.ImageFont,
    max_width: int,
) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        bbox = draw.textbbox((0, 0), candidate, font=font)
        if bbox[2] - bbox[0] <= max_width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def get_card_path(card_key: str) -> Path:
    """Рендерит (при первом обращении) и возвращает путь к PNG-баннеру 1200x500."""
    spec = _CARD_SPECS.get(card_key, _CARD_SPECS["welcome"])
    _RENDERED_DIR.mkdir(parents=True, exist_ok=True)
    out_path = _RENDERED_DIR / f"{card_key}.png"
    if out_path.exists():
        return out_path

    width, height = 1200, 500
    bg = Image.new("RGBA", (width, height), (11, 14, 20, 255))
    draw = ImageDraw.Draw(bg)

    # Внутренняя тёмная карточка (#141923) с тонкой рамкой
    pad = 28
    draw.rounded_rectangle(
        [pad, pad, width - pad, height - pad],
        radius=28,
        fill=(20, 25, 35, 255),
        outline=(255, 255, 255, 22),
        width=2,
    )

    accent_rgb = _hex_to_rgb(spec["accent"])
    # Тонкая акцентная полоса слева
    draw.rounded_rectangle(
        [pad + 34, pad + 56, pad + 42, height - pad - 56],
        radius=4,
        fill=(*accent_rgb, 255),
    )

    # Текстовый блок
    text_x = pad + 72
    max_text_w = 640

    font_eyebrow = _load_font(22, bold=True)
    font_title = _load_font(54, bold=True)
    font_sub = _load_font(27, bold=False)

    draw.text((text_x, pad + 74), spec["eyebrow"], font=font_eyebrow, fill=(*accent_rgb, 255))
    draw.text((text_x, pad + 118), spec["title"], font=font_title, fill=(245, 247, 252, 255))

    sub_lines = _wrap_text(draw, spec["subtitle"], font_sub, max_text_w)
    y_sub = pad + 206
    for line in sub_lines[:3]:
        draw.text((text_x, y_sub), line, font=font_sub, fill=(168, 178, 196, 255))
        y_sub += 38

    # Персонаж Пай-тян справа
    sticker_path = _ASSETS_DIR / spec["sticker"]
    if sticker_path.exists():
        try:
            sticker = Image.open(sticker_path).convert("RGBA")
            target_h = 410
            ratio = target_h / sticker.height
            target_w = int(sticker.width * ratio)
            sticker = sticker.resize((target_w, target_h), Image.Resampling.LANCZOS)
            pos_x = width - pad - target_w - 28
            pos_y = (height - target_h) // 2
            bg.alpha_composite(sticker, dest=(pos_x, pos_y))
        except Exception as e:
            logger.warning(f"Failed to composite sticker {sticker_path}: {e}")

    bg.convert("RGB").save(out_path, format="PNG", optimize=True)
    return out_path


def invalidate_card_cache() -> None:
    _FILE_ID_CACHE.clear()
    if _RENDERED_DIR.exists():
        for f in _RENDERED_DIR.glob("*.png"):
            try:
                f.unlink()
            except OSError:
                pass


async def send_or_edit_card(
    event: Message | CallbackQuery,
    *,
    card_key: str,
    caption: str,
    reply_markup: Optional[InlineKeyboardMarkup] = None,
) -> None:
    """
    Отправляет или плавно обновляет карточку Пай-тян на месте через edit_message_media.
    Кэширует Telegram file_id после первой загрузки баннера.
    """
    card_path = get_card_path(card_key)
    cached_id = _FILE_ID_CACHE.get(card_key)
    media: str | FSInputFile = cached_id if cached_id else FSInputFile(card_path)

    if isinstance(event, CallbackQuery) and event.message is not None:
        try:
            edited = await event.message.edit_media(
                media=InputMediaPhoto(media=media, caption=caption, parse_mode="HTML"),
                reply_markup=reply_markup,
            )
            if isinstance(edited, Message) and edited.photo:
                _FILE_ID_CACHE[card_key] = edited.photo[-1].file_id
            await event.answer()
            return
        except Exception as e:
            logger.debug(f"edit_media fallback to answer_photo for {card_key}: {e}")
            sent = await event.message.answer_photo(
                photo=media,
                caption=caption,
                parse_mode="HTML",
                reply_markup=reply_markup,
            )
            if sent.photo:
                _FILE_ID_CACHE[card_key] = sent.photo[-1].file_id
            await event.answer()
            return

    if isinstance(event, Message):
        sent = await event.answer_photo(
            photo=media,
            caption=caption,
            parse_mode="HTML",
            reply_markup=reply_markup,
        )
        if sent.photo:
            _FILE_ID_CACHE[card_key] = sent.photo[-1].file_id

