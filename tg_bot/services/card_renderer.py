from __future__ import annotations

import logging
import math
from collections import deque
from pathlib import Path
from typing import Dict, Optional

from aiogram.types import CallbackQuery, FSInputFile, InlineKeyboardMarkup, InputMediaPhoto, Message
from PIL import Image, ImageDraw, ImageFilter, ImageFont

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


def _cutout_sticker_background(img: Image.Image, tolerance: float = 38.0) -> Image.Image:
    """
    Удаляет однородный светло-серый фон вокруг стикера Пай-тян через BFS flood-fill
    от границ (с допуском Euclidean RGB <= 38) и сглаживает край альфа-канала (1px).
    """
    rgba = img.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()

    # Берём эталонный цвет фона с углов
    corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    bg_samples = [px[x, y][:3] for x, y in corners]
    bg_r = sum(c[0] for c in bg_samples) / 4.0
    bg_g = sum(c[1] for c in bg_samples) / 4.0
    bg_b = sum(c[2] for c in bg_samples) / 4.0

    tol_sq = tolerance * tolerance
    visited = bytearray(w * h)
    queue: deque[tuple[int, int]] = deque()

    def matches_bg(x: int, y: int) -> bool:
        r, g, b, a = px[x, y]
        if a < 10:
            return True
        dr = r - bg_r
        dg = g - bg_g
        db = b - bg_b
        return (dr * dr + dg * dg + db * db) <= tol_sq

    for x in range(w):
        for y in (0, h - 1):
            idx = y * w + x
            if not visited[idx] and matches_bg(x, y):
                visited[idx] = 1
                queue.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            idx = y * w + x
            if not visited[idx] and matches_bg(x, y):
                visited[idx] = 1
                queue.append((x, y))

    while queue:
        cx, cy = queue.popleft()
        px[cx, cy] = (0, 0, 0, 0)
        for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
            if 0 <= nx < w and 0 <= ny < h:
                nidx = ny * w + nx
                if not visited[nidx] and matches_bg(nx, ny):
                    visited[nidx] = 1
                    queue.append((nx, ny))

    # Лёгкое 1px размытие края альфа-канала для чистого контура без лесенок
    r_ch, g_ch, b_ch, a_ch = rgba.split()
    blurred_a = a_ch.filter(ImageFilter.GaussianBlur(radius=1.0))
    # Сохраняем внутреннюю непрозрачность, смягчая только внешний край
    a_px = a_ch.load()
    ba_px = blurred_a.load()
    for y in range(h):
        for x in range(w):
            if a_px[x, y] == 0:
                ba_px[x, y] = 0
            elif a_px[x, y] == 255 and ba_px[x, y] < 245:
                # краевой пиксель — оставляем сглаженным
                pass
            elif a_px[x, y] == 255:
                ba_px[x, y] = 255

    return Image.merge("RGBA", (r_ch, g_ch, b_ch, blurred_a))


def _create_radial_glow(size: int, rgb: tuple[int, int, int], max_alpha: int = 25) -> Image.Image:
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gpx = glow.load()
    half = size / 2.0
    for y in range(size):
        dy = (y - half) / half
        for x in range(size):
            dx = (x - half) / half
            dist = math.sqrt(dx * dx + dy * dy)
            if dist < 1.0:
                falloff = (1.0 - dist) ** 2.2
                alpha = int(max_alpha * falloff)
                if alpha > 0:
                    gpx[x, y] = (rgb[0], rgb[1], rgb[2], alpha)
    return glow


def get_card_path(card_key: str) -> Path:
    """Рендерит и возвращает путь к минималистичному PNG-баннеру 1200x480."""
    spec = _CARD_SPECS.get(card_key, _CARD_SPECS["welcome"])
    _RENDERED_DIR.mkdir(parents=True, exist_ok=True)
    out_path = _RENDERED_DIR / f"{card_key}_v2.png"
    if out_path.exists():
        return out_path

    width, height = 1200, 480
    bg = Image.new("RGBA", (width, height), (11, 14, 20, 255))
    draw = ImageDraw.Draw(bg)

    accent_rgb = _hex_to_rgb(spec["accent"])

    # Мягкое радиальное свечение за Пай-тян справа (alpha ~ 25, без рамок и полос)
    glow_size = 560
    glow = _create_radial_glow(glow_size, accent_rgb, max_alpha=25)
    bg.alpha_composite(glow, dest=(width - glow_size + 40, (height - glow_size) // 2))

    # Крупная и чистая типографика слева
    text_x = 76
    max_text_w = 640

    font_eyebrow = _load_font(22, bold=True)
    font_title = _load_font(56, bold=True)
    font_sub = _load_font(27, bold=False)

    draw.text((text_x, 96), spec["eyebrow"], font=font_eyebrow, fill=(*accent_rgb, 255))
    draw.text((text_x, 142), spec["title"], font=font_title, fill=(245, 247, 252, 255))

    sub_lines = _wrap_text(draw, spec["subtitle"], font_sub, max_text_w)
    y_sub = 232
    for line in sub_lines[:3]:
        draw.text((text_x, y_sub), line, font=font_sub, fill=(168, 178, 196, 255))
        y_sub += 40

    # Персонаж Пай-тян справа с прозрачным вырезом фона
    sticker_path = _ASSETS_DIR / spec["sticker"]
    if sticker_path.exists():
        try:
            raw_sticker = Image.open(sticker_path)
            cutout = _cutout_sticker_background(raw_sticker, tolerance=38.0)
            target_h = 416
            ratio = target_h / cutout.height
            target_w = int(cutout.width * ratio)
            cutout = cutout.resize((target_w, target_h), Image.Resampling.LANCZOS)
            pos_x = width - target_w - 56
            pos_y = (height - target_h) // 2
            bg.alpha_composite(cutout, dest=(pos_x, pos_y))
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
