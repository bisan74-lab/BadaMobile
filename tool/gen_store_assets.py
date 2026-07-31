#!/usr/bin/env python3
"""Play Console에 올릴 그래픽 자산을 만든다.

- `store_assets/play_icon_512.png` — 스토어 아이콘(512x512)
- `store_assets/feature_graphic_1024x500.png` — 피처 그래픽

앱 아이콘(`assets/icon/app_icon.png`)과 앱 배경색을 그대로 쓰므로 스토어
페이지와 실제 앱의 인상이 어긋나지 않는다. 스크린샷은 여기서 만들지
않는다 — 실제 기기에서 찍은 것만 스토어 정책에 맞는다.

    python3 tool/gen_store_assets.py
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'store_assets'

# 앱과 같은 색(pubspec의 adaptive_icon_background, 다크 테마 배경)
NAVY = (7, 22, 43)
NAVY_LIGHT = (14, 42, 76)
CYAN = (94, 234, 240)
BLUE = (56, 130, 246)
TEXT = (233, 242, 255)
MUTED = (150, 180, 214)

# 컨테이너에 있는 한글 지원 폰트(공개 라이선스). 없으면 한글이 두부(□)로 나온다.
FONT_PATH = '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc'


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_PATH, size)


def make_icon() -> None:
    """스토어 아이콘: 512x512, 투명 없는 32비트 PNG.

    구글이 모서리를 직접 둥글게 마스킹하므로 여기서 깎지 않는다.
    """
    src = Image.open(ROOT / 'assets/icon/app_icon.png').convert('RGBA')
    bg = Image.new('RGBA', src.size, NAVY + (255,))
    bg.alpha_composite(src)
    icon = bg.convert('RGB').resize((512, 512), Image.LANCZOS)
    icon.save(OUT / 'play_icon_512.png', 'PNG', optimize=True)


def _gradient(size: tuple[int, int]) -> Image.Image:
    """왼쪽 아래가 밝은 대각선 그라데이션(바다 위 새벽빛 느낌)."""
    w, h = size
    img = Image.new('RGB', size)
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = (x / w) * 0.55 + (1 - y / h) * 0.45
            t = t ** 1.6
            px[x, y] = tuple(
                round(a + (b - a) * t) for a, b in zip(NAVY_LIGHT, NAVY)
            )
    return img


def _wind_streaks(size: tuple[int, int]) -> Image.Image:
    """앱의 바람 지도를 연상시키는 흐름선. 고정 시드라 매번 같은 그림이 나온다."""
    w, h = size
    layer = Image.new('RGBA', size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rng = random.Random(20260731)

    def flow(x: float, y: float) -> float:
        """부드럽게 변하는 벡터장의 각도(라디안)."""
        return (
            math.sin(x / 260.0) * 0.55
            + math.cos(y / 150.0) * 0.40
            + math.sin((x + y) / 420.0) * 0.30
        )

    for _ in range(150):
        x, y = rng.uniform(-60, w + 60), rng.uniform(-30, h + 30)
        speed = rng.uniform(0.35, 1.0)
        alpha = int(14 + 42 * speed)
        color = tuple(
            round(a + (b - a) * speed) for a, b in zip(BLUE, CYAN)
        ) + (alpha,)
        pts = [(x, y)]
        for _ in range(rng.randint(28, 62)):
            a = flow(x, y)
            x += math.cos(a) * 7.0
            y += math.sin(a) * 7.0
            pts.append((x, y))
        d.line(pts, fill=color, width=max(1, round(speed * 3)), joint='curve')

    return layer.filter(ImageFilter.GaussianBlur(0.7))


def _glow(size: tuple[int, int], center: tuple[int, int], radius: int,
          color: tuple[int, int, int], strength: int) -> Image.Image:
    layer = Image.new('RGBA', size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(
        [center[0] - radius, center[1] - radius,
         center[0] + radius, center[1] + radius],
        fill=color + (strength,),
    )
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.55))


def make_feature_graphic() -> None:
    """피처 그래픽: 1024x500, 투명 없음.

    스토어 배치에 따라 가장자리가 잘릴 수 있어 글자는 안쪽에만 둔다.
    """
    size = (1024, 500)
    img = _gradient(size).convert('RGBA')
    img.alpha_composite(_glow(size, (250, 250), 250, CYAN, 46))
    img.alpha_composite(_wind_streaks(size))

    # 아이콘은 모서리를 둥글게 깎는다 — 배경이 더 밝아서 각진 채로 두면
    # 그림이 아니라 덧붙인 사각형처럼 보인다(홈 화면에서 보이는 모양과도 다르다).
    side = 272
    icon = Image.open(ROOT / 'assets/icon/app_icon.png').convert('RGBA')
    icon = icon.resize((side, side), Image.LANCZOS)
    mask = Image.new('L', (side * 4, side * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, side * 4 - 1, side * 4 - 1], radius=side * 4 * 22 // 100, fill=255
    )
    icon.putalpha(mask.resize((side, side), Image.LANCZOS))

    ix, iy = 86, (size[1] - side) // 2
    img.alpha_composite(_glow(size, (ix + side // 2, iy + side // 2), 170, CYAN, 40))
    img.alpha_composite(icon, (ix, iy))

    d = ImageDraw.Draw(img)
    tx = 410
    # 제목은 같은 글자를 살짝 겹쳐 그려 굵기를 낸다(이 폰트에 볼드가 없다).
    for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        d.text((tx + dx, 150 + dy), '바다윈디', font=font(92), fill=TEXT)
    d.text((tx, 262), '물때 · 조석 · 바람 지도', font=font(40), fill=CYAN)
    d.text((tx, 322), '전국 항구의 물때부터 해상 바람까지',
           font=font(29), fill=MUTED)
    d.text((tx, 362), '한 앱에서, 무료로', font=font(29), fill=MUTED)

    img.convert('RGB').save(
        OUT / 'feature_graphic_1024x500.png', 'PNG', optimize=True
    )


if __name__ == '__main__':
    OUT.mkdir(exist_ok=True)
    make_icon()
    make_feature_graphic()
    for p in sorted(OUT.glob('*.png')):
        print(p.relative_to(ROOT), Image.open(p).size, f'{p.stat().st_size:,}B')
