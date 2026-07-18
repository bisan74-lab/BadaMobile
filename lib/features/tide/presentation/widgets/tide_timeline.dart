import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/sea_backdrop.dart';
import '../../data/models/tide_data.dart';

/// 만조/간조를 세로 0~24시 타임라인 위에 그래픽 카드로 배치해 보여준다.
/// 바다타임 앱의 물때 화면(사진 참고)을 본떠, 바다색 배경 위에 시각축과
/// 만조(붉은색)/간조(파란색) 카드, 현재 시각선을 함께 그린다.
class TideTimeline extends StatelessWidget {
  const TideTimeline({
    super.key,
    required this.extremes,
    required this.now,
    this.showBackdrop = true,
  });

  final List<TideExtreme> extremes;
  final DateTime? now;

  /// 직접 그린 바다 배경 표시 여부(설정 > 템플릿 > 배경 그래픽).
  final bool showBackdrop;

  static const double _height = 512;

  /// 만조는 축 왼쪽, 간조는 축 오른쪽에 배치해 양쪽 공간을 고르게 쓴다.
  static const double _axisFraction = 0.5;
  static const double _cardGap = 12;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF082238),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final axisX = size.width * _axisFraction;
          final cardWidth = axisX - 12 - _cardGap;
          const top = 28.0;
          // 아래쪽 여백을 더 확보해 24시 라벨·마지막 카드가 잘리지 않게 한다.
          final bottom = size.height - 48.0;
          final trackHeight = bottom - top;

          double yForMinutes(int minutes) =>
              top + (minutes / (24 * 60)) * trackHeight;
          double yFor(DateTime t) => yForMinutes(t.hour * 60 + t.minute);

          return Stack(
            children: [
              // 직접 그린 바다 배경(라이선스 없음).
              if (showBackdrop)
                const Positioned.fill(child: SeaBackdrop(opacity: 0.9)),
              Positioned(
                left: axisX - 2,
                top: top,
                child: Container(
                  width: 4,
                  height: trackHeight,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              for (final h in const [0, 6, 12, 18, 24])
                Positioned(
                  left: axisX - 22,
                  top: yForMinutes(h * 60) - 10,
                  child: Container(
                    width: 44,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E3454),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      '$h시',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              if (now != null)
                Positioned(
                  left: 16,
                  right: 16,
                  top: yFor(now!) - 1,
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.amberAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1.5,
                          color: Colors.amberAccent.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              for (var i = 0; i < extremes.length; i++) ...[
                Positioned(
                  left: axisX - 5,
                  top: yFor(extremes[i].time) - 5,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: extremes[i].isHigh
                          ? const Color(0xFFC1425C)
                          : const Color(0xFF3E72B8),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
                Positioned(
                  left: extremes[i].isHigh ? 12 : axisX + _cardGap,
                  top: yFor(extremes[i].time) - 26,
                  width: cardWidth,
                  child: _ExtremeCard(
                    extreme: extremes[i],
                    deltaCm: i == 0
                        ? null
                        : extremes[i].heightCm - extremes[i - 1].heightCm,
                    alignEnd: extremes[i].isHigh,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ExtremeCard extends StatelessWidget {
  const _ExtremeCard({
    required this.extreme,
    required this.deltaCm,
    required this.alignEnd,
  });

  final TideExtreme extreme;
  final double? deltaCm;

  /// true면 축 왼쪽(만조) 카드 — 내용을 오른쪽(축 방향)으로 정렬한다.
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final isHigh = extreme.isHigh;
    final bg = isHigh ? const Color(0xFFB0334A) : const Color(0xFF29508C);
    final crossAlign = alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    return Container(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: crossAlign,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${isHigh ? '만조' : '간조'} ${formatHm(extreme.time)}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '(${extreme.heightCm.round()})',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (deltaCm != null) ...[
                const SizedBox(width: 4),
                Icon(
                  deltaCm! >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12,
                  color: Colors.white,
                ),
                Text(
                  '${deltaCm!.abs().round()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 조류 세기를 정성적으로 보여주는 진행 막대(윤 예: "최대").
class TideCurrentStrengthBar extends StatelessWidget {
  const TideCurrentStrengthBar({
    super.key,
    required this.fraction,
    required this.label,
  });

  /// 0~1, 하루 조위 변화폭 기준의 상대적 세기.
  final double fraction;
  final String label;

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    return Row(
      children: [
        Text(
          '조류세기',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: Colors.white70),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              FractionallySizedBox(
                widthFactor: f == 0 ? 0.02 : f,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3E72B8), Color(0xFFC1425C)],
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
