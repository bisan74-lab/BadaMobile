/// 오른쪽 세로 메뉴에 쓰는 아이콘+라벨 칩.
///
/// 화면에 이런 세로 메뉴가 **두 벌** 뜬다 — 물때&날씨 화면 자체의 미니 메뉴
/// (물때·낚시정보·날씨·물때달력·조위)와 앱 탭 레일(물때날씨·바람지도·설정).
/// 둘이 같은 오른쪽 가장자리를 나눠 쓰므로, 글자 배율에 따라 **얼마나
/// 높아지는지를 양쪽이 같은 식으로 알아야** 서로 겹치지 않는다.
/// 그래서 칩 모양과 높이 계산을 여기 한곳에 둔다.
///
/// 2026-08-06 사용자 제보: 큰 글자 기기에서 "낚시정보"와 "물때날씨"가 서로
/// 겹쳐 그려졌다. 미니 메뉴가 레일 자리로 비워 두던 값이 **1.0배 기준 높이에
/// 고정**돼 있어서, 배율이 오르면 레일만 길어지고 비운 공간은 그대로였다.
library;

import 'package:flutter/material.dart';

/// 칩 가로 폭. 라벨 네 글자가 배율 1.0에서 한 줄에 들어가는 크기.
const double navChipWidth = 52;

/// 칩 사이 세로 간격.
const double navChipGap = 5;

/// 아이콘 크기와 세로 여백.
const double _iconSize = 16;
const double _iconGap = 2;
const double _vPad = 5;

/// 라벨 기준 글자 크기.
const double navChipFontSize = 10;

/// **라벨 배율 상한.** 칩 폭이 고정된 UI 가구라 배율을 그대로 받으면 높이가
/// 끝없이 늘어 다른 메뉴를 덮는다(광고 자리와 같은 이유의 예외). 상한을
/// 두더라도 접근성을 버리지 않도록:
/// - 기준 글자를 8.5 → [navChipFontSize]로 키웠고,
/// - 각 칩에 [Semantics] 라벨을 달아 스크린리더는 전체를 그대로 읽는다.
///
/// **본문 화면에는 이 상한을 쓰지 말 것** — 사용자의 접근성 설정을 무시하게 된다.
const double navChipMaxTextScale = 1.5;

/// [context]의 글자 배율에서 이 칩들이 세로로 차지하는 높이(간격 포함).
///
/// 라벨이 칩 폭 안에서 몇 줄이 되는지까지 실제로 재므로, 배율이 올라
/// 두 줄이 되는 순간도 그대로 반영된다.
double navChipsHeight(BuildContext context, List<String> labels) {
  final scaler = _cappedScaler(context);
  // **칩이 실제로 쓰는 것과 같은 스타일로 재야 한다.** fontSize만 준 맨
  // TextStyle로 재면 글꼴·줄높이가 달라 실제보다 20%쯤 낮게 나오고, 그만큼
  // 덜 비워서 탭 레일과 겹친다(2026-08-06에 이 오차로 한 번 더 겹쳤다).
  final style = DefaultTextStyle.of(
    context,
  ).style.copyWith(fontSize: navChipFontSize);
  var total = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout(maxWidth: navChipWidth);
    total += _vPad * 2 + _iconSize + _iconGap + painter.height + navChipGap;
  }
  // 글꼴 대체(fallback)나 줄높이 차이로 몇 px씩 모자랄 수 있다. **모자라면
  // 겹치고 남으면 여백일 뿐**이라 넉넉한 쪽으로 올림한다.
  return total + 8;
}

TextScaler _cappedScaler(BuildContext context) =>
    MediaQuery.textScalerOf(context).clamp(maxScaleFactor: navChipMaxTextScale);

/// 세로 메뉴 칩 하나.
class NavChip extends StatelessWidget {
  const NavChip({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: navChipGap),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            width: navChipWidth,
            padding: const EdgeInsets.symmetric(vertical: _vPad),
            decoration: BoxDecoration(
              color: selected ? primary : Colors.black54,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: _iconSize, color: Colors.white),
                const SizedBox(height: _iconGap),
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: navChipMaxTextScale,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: navChipFontSize,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
