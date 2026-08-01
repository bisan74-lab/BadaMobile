#!/usr/bin/env python3
"""앱의 지역 목록(`sample_locations.dart`)을 파이썬에서 그대로 읽는다.

서버 수집 스크립트와 앱이 **같은 지역 목록**을 써야 파일에 빠지는 지역이
없다. 목록을 두 벌로 관리하면 어긋나므로 Dart 원본 하나만 둔다.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'lib/features/locations/data/sample_locations.dart'


def load() -> list[dict]:
    text = SRC.read_text(encoding='utf-8')
    out: list[dict] = []
    for block in re.findall(r'SeaLocation\((.*?)\n  \)', text, re.S):

        def field(name: str, cast=str):
            m = re.search(rf"{name}:\s*'?([^,'\n]+)'?", block)
            return cast(m.group(1)) if m else None

        loc = {
            'id': field('id'),
            'name': field('name'),
            'region': field('region'),
            'lat': field('latitude', float),
            'lon': field('longitude', float),
        }
        if loc['id'] and loc['lat'] is not None and loc['lon'] is not None:
            out.append(loc)
    if not out:
        raise RuntimeError(f'지역 목록을 읽지 못했습니다: {SRC}')
    return out


if __name__ == '__main__':
    locs = load()
    print(f'{len(locs)}곳')
    for loc in locs[:5]:
        print(' ', loc)
