"""배경 사진을 '앱에서 보이는 대로' 미리 본다.

물때 화면은 배경 위에 글자 가독성용 검은 그라디언트를 덮는다
(tide_screen.dart: 위 35% → 가운데 15% → 아래 35%). 원본만 보고 밝기를
정하면 실제 화면에서는 훨씬 어둡다.
"""

import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

SCRIM = [(0.0, 0.35), (0.5, 0.15), (1.0, 0.35)]


def with_scrim(path: Path) -> Image.Image:
    img = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    h = img.shape[0]
    ys = np.linspace(0, 1, h)
    a = np.interp(ys, [s[0] for s in SCRIM], [s[1] for s in SCRIM])
    out = img * (1 - a[:, None, None])
    return Image.fromarray(out.astype(np.uint8))


def main() -> None:
    # 저장소 안(`tool/`)에 PNG를 떨어뜨리지 않는다 — 미리보기는 버릴 파일이다.
    out_dir = Path(tempfile.gettempdir()) / 'bada_preview'
    out_dir.mkdir(exist_ok=True)
    for name in sys.argv[1:]:
        src = Path('/home/user/BadaMobile/assets/images') / f'{name}.jpg'
        both = Image.new('RGB', (960, 800))
        raw = Image.open(src).resize((480, 800), Image.LANCZOS)
        both.paste(raw, (0, 0))
        both.paste(with_scrim(src).resize((480, 800), Image.LANCZOS), (480, 0))
        dst = out_dir / f'inapp_{name}.png'
        both.save(dst)
        print(f'{dst}  (왼쪽=원본, 오른쪽=앱에서 보이는 모습)')


if __name__ == '__main__':
    main()
