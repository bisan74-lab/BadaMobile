#!/usr/bin/env python3
"""물때&날씨 화면 배경 사진을 만든다(자체 생성 — 라이선스 없음).

    python3 tool/gen_backgrounds.py

두 장을 그린다.

- `sea_bg_night.jpg` **달밤 바다** — 달이 높이의 28% 지점에 있어 날짜 줄·물때
  칩에 가려 잘 안 보였다(2026-08-06 사용자 제보). 달을 [SKY_SAFE_TOP]으로
  올린다.
- `sea_bg_morning.jpg` **밝은 아침 바다** — **파란 하늘·파란 바다에 황금빛
  해**가 떠 햇살이 퍼지는 그림. 해는 달보다 조금 더 위([SUN_Y]).

  색을 고를 때 두 번 헛짚었다. ① 바탕까지 금빛으로 물들였더니 해와 배경의
  색이 같아져 **아무리 밝혀도 해가 배경에서 떨어져 나오지 않았다** —
  금빛은 해와 햇살에서만 나와야 한다. ② 파란 하늘에 노란빛을 **더하기만**
  했더니 R·G가 먼저 포화돼 햇살이 흰색으로 나왔다 — 파랑을 **빼야** 금빛이
  산다. 그래서 `_sun_rays`·`_glow`·`_light_path`의 색 인자는 음수를 받는
  **RGB 증분**이다.

**원본 사진을 오려 옮기지 않고 통째로 다시 그린다.** 예전엔 기존
`sea_bg_night.jpg`에서 달과 달무리만 떼어 위로 옮기려 했는데 세 번 실패했다:
① 원래 자리에서 달무리를 빼면 하늘 밝기 추정이 조금만 어긋나도 **어두운
고리**가 남고, ② 덮을 하늘을 좌우 대칭으로 떠 오면 마스크가 원래 달무리를
되비쳐 **유령 달**이 생기고, ③ 왼쪽 조각을 이어 붙이면 조각 안의 **섬이
복제**되고 네모난 이음매가 보였다. 게다가 달을 찾는 기준(가장 밝은 픽셀들의
무게중심)부터 틀렸다 — **별이 달 원반보다 밝아서** 중심이 별 쪽으로 끌려갔다.

그림 자체를 만들면 달·해 위치가 그냥 **인자**라 이 문제가 전부 사라진다.
두 그림이 같은 뼈대(하늘·바다 그라디언트 → 빛무리 → 물빛 → 섬 → 수평선)를
쓰므로 나중에 배경을 더 추가하기도 쉽다.
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/images'
SIZE = (1440, 2400)

# 화면에서 이 높이 아래로는 날짜 줄·물때 칩·조류세기가 덮는다. 해·달은
# 이 위에 둬야 보인다.
SKY_SAFE_TOP = 0.12

# 수평선. 기존 배경들과 같은 자리(높이의 34%)라 화면을 바꿔 껴도 어색하지 않다.
HORIZON = 0.34

# 해·달의 가로 위치(기존 달밤 바다와 같은 자리).
LIGHT_X = 0.68

# **해만 달보다 더 위에 둔다**(사용자 요구, 2026-08-06). 달은 [SKY_SAFE_TOP]
# 그대로가 좋다는 확인을 받았으므로 공용 상수를 건드리지 않고 해만 따로 뺀다.
#
# 앱바가 투명하고 `extendBodyBehindAppBar`라 이 높이도 화면에 그대로 보인다.
# 다만 상태바가 위쪽 3~4%를 덮으므로 이보다 더 올리면 해가 잘린다.
SUN_Y = 0.085


# ── 공통 그리기 조각 ───────────────────────────────────────────────
def _vertical_gradient(stops: list[tuple[float, tuple[int, int, int]]]):
    """(위치 0~1, RGB) 제어점으로 세로 그라디언트를 만든다."""
    w, h = SIZE
    ys = np.linspace(0, 1, h)
    pos = np.array([s[0] for s in stops])
    cols = np.array([s[1] for s in stops], dtype=np.float32)
    out = np.empty((h, 3), dtype=np.float32)
    for c in range(3):
        out[:, c] = np.interp(ys, pos, cols[:, c])
    return np.broadcast_to(out[:, None, :], (h, w, 3)).copy()


def _glow(center, radius, color, strength):
    """[center]를 중심으로 부드럽게 퍼지는 빛무리(더하기용)."""
    layer = Image.new('L', SIZE, 0)
    d = ImageDraw.Draw(layer)
    cx, cy = center
    # 여러 겹으로 그려 가장자리가 자연스럽게 사라지게.
    for i in range(14, 0, -1):
        r = radius * i / 14
        a = int(strength * (1 - i / 14) ** 1.6)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=a)
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.18))
    g = np.asarray(layer).astype(np.float32)[:, :, None] / 255.0
    return g * np.array(color, dtype=np.float32)


def _disk(center, radius, color, softness=2.0):
    """또렷한 원반(해·달 본체)."""
    layer = Image.new('L', SIZE, 0)
    cx, cy = center
    ImageDraw.Draw(layer).ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius], fill=255
    )
    layer = layer.filter(ImageFilter.GaussianBlur(softness))
    m = np.asarray(layer).astype(np.float32)[:, :, None] / 255.0
    return m, np.array(color, dtype=np.float32)


def _stars(count: int, sky_bottom: int, seed: int = 11):
    """하늘에 뿌리는 별. 수평선에 가까울수록 옅어진다."""
    w, h = SIZE
    rng = np.random.default_rng(seed)
    layer = Image.new('L', SIZE, 0)
    d = ImageDraw.Draw(layer)
    for _ in range(count):
        x = rng.uniform(0, w)
        y = rng.uniform(0, sky_bottom)
        fade = 1 - (y / sky_bottom) ** 1.6  # 아래쪽은 대기에 묻힌다
        r = rng.uniform(1.0, 2.6)
        a = int(rng.uniform(70, 255) * fade)
        if a <= 0:
            continue
        d.ellipse([x - r, y - r, x + r, y + r], fill=a)
    layer = layer.filter(ImageFilter.GaussianBlur(0.6))
    return np.asarray(layer).astype(np.float32)[:, :, None] / 255.0


def _clouds(sky_bottom: int, seed: int = 5):
    """하늘에 낮게 깔린 옅은 구름결(가로로 길쭉한 덩어리)."""
    w, h = SIZE
    rng = np.random.default_rng(seed)
    layer = Image.new('L', SIZE, 0)
    d = ImageDraw.Draw(layer)
    for _ in range(70):
        cx = rng.uniform(-100, w + 100)
        cy = rng.uniform(sky_bottom * 0.05, sky_bottom * 0.95)
        rw = rng.uniform(90, 320)
        rh = rw * rng.uniform(0.16, 0.30)
        d.ellipse([cx - rw, cy - rh, cx + rw, cy + rh], fill=int(rng.uniform(40, 120)))
    layer = layer.filter(ImageFilter.GaussianBlur(48))
    return np.asarray(layer).astype(np.float32)[:, :, None] / 255.0


def _light_path(horizon: int, x_frac: float, color, seed: int = 7):
    """수평선 아래로 번지는 빛의 길(달빛·햇빛이 물결에 부서지는 자국).

    아래로 갈수록 **넓어지고 알갱이도 굵어진다** — 가까운 물결일수록 크게
    보이는 원근을 흉내 낸 것이라, 폭을 고정하면 세로 띠를 붙여 놓은 것처럼
    보인다.
    """
    w, h = SIZE
    rng = np.random.default_rng(seed)
    # 굵기가 다른 잡음을 겹쳐 물결이 부서진 느낌을 낸다.
    n = np.zeros((h, w), dtype=np.float32)
    for scale, weight in ((16, 0.5), (8, 0.32), (4, 0.18)):
        small = rng.random((h // scale + 2, w // scale + 2)).astype(np.float32)
        big = (
            Image.fromarray((small * 255).astype(np.uint8))
            .resize(SIZE, Image.BICUBIC)
            .filter(ImageFilter.GaussianBlur(scale * 0.25))
        )
        n += weight * (np.asarray(big).astype(np.float32) / 255.0)

    yy, xx = np.mgrid[0:h, 0:w]
    depth = np.clip((yy - horizon) / (h - horizon), 0, 1)
    half = w * (0.055 + 0.30 * depth)  # 아래로 갈수록 넓게
    band = np.exp(-((xx - w * x_frac) / half) ** 2)
    fade = np.sin(np.pi * depth**0.55) ** 1.2  # 수평선·맨 아래는 잦아든다
    amp = band * fade * np.clip((n - 0.57) * 3.2, 0, 1)
    return amp[:, :, None] * np.array(color, dtype=np.float32)


def _sun_rays(
    center,
    horizon: int,
    color,
    strength: float,
    seed: int = 21,
    blur: float = 14,
):
    """해에서 뻗어 나오는 **햇살 줄기**(부챗살 모양 빛기둥).

    "햇살이 내리쬐는 느낌"을 내는 핵심이고, 기존 `한낮 바다`(차가운 파랑 +
    흰 구름)와 아침을 눈에 띄게 갈라 놓는 요소이기도 하다. 밝기만 올리면
    두 배경이 비슷해 보인다.

    각도에 대한 사인 몇 개를 겹쳐 굵기가 제각각인 줄기를 만들고, 해에서
    멀어질수록·수평선을 지날수록 잦아들게 한다.

    [color]는 색이 아니라 **더할 RGB 증분이고, 음수를 넣을 수 있다.**
    파란 하늘에 노란빛을 그냥 더하면 R·G가 먼저 포화돼 줄기가 **금빛이
    아니라 흰색**으로 나온다(2026-08-07에 실제로 그렇게 나왔다). 파랑을
    **빼야** 금빛이 산다 — 예: `(90, 46, -70)`.
    """
    w, h = SIZE
    cx, cy = center
    yy, xx = np.mgrid[0:h, 0:w]
    ang = np.arctan2(yy - cy, xx - cx)
    r = np.hypot(xx - cx, yy - cy)

    rng = np.random.default_rng(seed)
    beams = np.zeros((h, w), dtype=np.float32)
    for freq, weight in ((5, 0.44), (9, 0.30), (14, 0.16), (23, 0.10)):
        beams += weight * np.sin(freq * ang + rng.uniform(0, 2 * np.pi))
    beams = np.clip(beams * 1.15 + 0.34, 0, 1) ** 1.7

    # 해 바로 옆(빛무리에 묻힘)과 아주 먼 곳에서는 줄기가 보이지 않는다.
    near = np.clip((r - w * 0.10) / (w * 0.18), 0, 1)
    far = np.clip(1 - (r - w * 0.28) / (w * 1.15), 0, 1) ** 1.3
    # 수면 위에서는 빠르게 잦아든다 — 물 위까지 줄기가 뻗으면 어색하다.
    below = np.clip(1 - (yy - horizon * 0.72) / (h * 0.13), 0, 1)

    amp = beams * near * far * below * strength
    amp = np.asarray(
        Image.fromarray((np.clip(amp, 0, 1) * 255).astype(np.uint8)).filter(
            ImageFilter.GaussianBlur(blur)
        )
    ).astype(np.float32) / 255.0
    return amp[:, :, None] * np.array(color, dtype=np.float32)


def _island(img, horizon: int, color, opacity: float):
    """수평선 왼쪽의 먼 섬(다른 배경들과 같은 자리)."""
    silhouette = Image.new('L', SIZE, 0)
    d = ImageDraw.Draw(silhouette)
    base = horizon + 3
    pts = [(0, base)]
    for dx, dy in [
        (60, -26),
        (120, -46),
        (190, -30),
        (250, -44),
        (310, -18),
        (360, -6),
    ]:
        pts.append((dx, base + dy))
    pts.append((380, base))
    d.polygon(pts, fill=255)
    m = np.asarray(silhouette.filter(ImageFilter.GaussianBlur(1.2)))
    m = (m.astype(np.float32) / 255.0)[:, :, None] * opacity
    return img * (1 - m) + np.array(color, dtype=np.float32) * m


def _save(img, dst: Path):
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    out = out.filter(ImageFilter.GaussianBlur(0.4))
    out.save(dst, quality=88, optimize=True)


# ── 1. 달밤 바다 ───────────────────────────────────────────────────
def make_night(dst: Path) -> None:
    w, h = SIZE
    horizon = int(h * HORIZON)
    moon = (int(w * LIGHT_X), int(h * SKY_SAFE_TOP))

    # 제어점은 기존 `sea_bg_night.jpg`의 줄별 색을 그대로 뜬 것이라 색감이
    # 예전 배경과 거의 같다.
    img = _vertical_gradient([
        (0.00, (9, 15, 35)),
        (0.10, (11, 19, 43)),
        (0.20, (8, 18, 45)),
        (0.30, (13, 24, 56)),
        (0.34, (18, 33, 66)),  # 수평선
        (0.40, (26, 44, 83)),
        (0.50, (24, 40, 76)),
        (0.60, (11, 24, 56)),
        (0.75, (10, 22, 46)),
        (1.00, (4, 11, 27)),
    ])

    img += _clouds(horizon) * np.array([14, 19, 32], dtype=np.float32)
    img += _stars(650, horizon) * np.array([198, 210, 244], dtype=np.float32)

    # 달무리 → 달 원반 순서. 원반을 나중에 덮어야 가장자리가 또렷하다.
    img += _glow(moon, 470, (150, 168, 205), 150)
    img += _glow(moon, 165, (208, 216, 235), 190)
    m, c = _disk(moon, 62, (238, 240, 226), softness=2.4)
    img = img * (1 - m) + c * m
    img += _light_path(horizon, LIGHT_X, (150, 172, 210)) * 0.55

    img = _island(img, horizon, (6, 10, 22), 0.92)
    img[horizon : horizon + 2] = np.clip(img[horizon : horizon + 2] + 12, 0, 255)

    _save(img, dst)
    print(f'  → {dst.name}: 달을 높이의 {SKY_SAFE_TOP:.0%} 지점에')


# ── 2. 밝은 아침 바다 ──────────────────────────────────────────────
def make_morning(dst: Path) -> None:
    w, h = SIZE
    horizon = int(h * HORIZON)
    sun = (int(w * LIGHT_X), int(h * SUN_Y))

    # **파란 하늘·파란 바다 위에 황금빛 해**(사용자 요구, 2026-08-07).
    #
    # 앞선 판은 바탕색까지 금빛으로 물들였다가 "선명하지 않다"는 제보를
    # 받았다. 원인은 밝기가 아니라 **금빛을 바탕에 깔았다는 것** — 해와
    # 배경의 색이 같으니 아무리 밝혀도 해가 배경에서 떨어져 나오지 않는다.
    # 그래서 바탕은 하늘색으로 되돌리고, **금빛은 해와 햇살에서만** 나오게
    # 한다. 파랑 위의 금빛이라 대비가 서고, 그래야 `한낮 바다`와도 계속
    # 구분된다(그쪽은 금빛 요소가 아예 없다).
    #
    # **화면에서는 이보다 어둡게 보인다.** 물때 화면이 글자 가독성을 위해
    # 위 35% · 가운데 15% · 아래 35%의 검은 그라디언트를 덮기 때문이다
    # (`tide_screen.dart`). 그 막을 얇게 하면 모든 배경에서 글자가 읽기
    # 힘들어지므로 **원본 쪽을 밝게** 해서 막을 견디게 한다.
    # `tool/preview_inapp.py`로 막을 씌운 모습을 보고 맞춘다.
    img = _vertical_gradient([
        (0.00, (74, 152, 222)),  # 맑은 하늘색
        (0.14, (120, 184, 234)),
        (0.26, (174, 214, 240)),
        (0.34, (222, 234, 240)),  # 수평선은 옅게
        (0.35, (108, 178, 218)),  # 바다도 하늘색 계열
        (0.50, (72, 148, 200)),
        (0.72, (44, 112, 170)),
        (1.00, (24, 74, 132)),
    ])

    # 구름은 옅게만 — 짙으면 하늘이 뿌예져 해가 묻힌다.
    img += _clouds(horizon, seed=9) * np.array([26, 30, 34], dtype=np.float32)

    # 햇살 줄기 → 빛무리 → 원반 순서. 줄기를 먼저 깔아야 빛무리가 그 위를
    # 부드럽게 덮어 해 주변에서 줄기가 튀지 않는다.
    #
    # **빛무리를 넓게 깔면 안 된다.** 예전엔 반지름 640까지 퍼뜨렸는데,
    # 하늘 절반이 뿌옇게 흐려지면서 정작 해가 그 안개에 묻혔다. 지금은
    # 해에 바짝 붙는 코로나만 남긴다.
    img += _sun_rays(sun, horizon, (104, 54, -76), 0.62, blur=8)
    img += _glow(sun, 340, (150, 92, -46), 190)
    img += _glow(sun, 160, (255, 224, 146), 74)
    m, c = _disk(sun, 96, (255, 248, 214), softness=2.5)
    img = img * (1 - m) + c * m
    img += _light_path(horizon, LIGHT_X, (232, 156, 34), seed=3) * 1.1

    img = _island(img, horizon, (72, 104, 132), 0.62)
    img[horizon : horizon + 2] = np.clip(img[horizon : horizon + 2] + 22, 0, 255)

    _save(img, dst)
    print(f'  → {dst.name}: 해를 높이의 {SKY_SAFE_TOP:.0%} 지점에')


def main() -> None:
    print('배경 사진 생성')
    make_night(OUT / 'sea_bg_night.jpg')
    make_morning(OUT / 'sea_bg_morning.jpg')
    for name in ['sea_bg_night.jpg', 'sea_bg_morning.jpg']:
        p = OUT / name
        print(f'  {name}: {Image.open(p).size} {p.stat().st_size:,}B')


if __name__ == '__main__':
    main()
