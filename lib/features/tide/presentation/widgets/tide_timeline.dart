import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../data/models/tide_data.dart';

/// 만조/간조를 세로 0~24시 타임라인 위에 그래픽 카드로 배치해 보여준다.
/// 바다타임 앱의 물때 화면(사진 참고)을 본떠, 바다색 배경 위에 시각축과
/// 만조(붉은색)/간조(파란색) 카드, 현재 시각선을 함께 그린다.
class TideTimeline extends StatelessWidget {
  const TideTimeline({super.key, required this.extremes, required this.now});

  final List<TideExtreme> extremes;
  final DateTime? now;

  static const double _height = 460;
  static const double _axisFraction = 0.4;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E5C8A), Color(0xFF0E3454), Color(0xFF082238)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final axisX = size.width * _axisFraction;
          const top = 24.0;
          final bottom = size.height - 24.0;
          final trackHeight = bottom - top;

          double yForMinutes(int minutes) =>
              top + (minutes / (24 * 60)) * trackHeight;
          double yFor(DateTime t) => yForMinutes(t.hour * 60 + t.minute);

          return Stack(
            children: [
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
                  left: axisX + 10,
                  top: yForMinutes(h * 60) - 8,
                  child: Text(
                    '$h시',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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
                  left: 12,
                  top: yFor(extremes[i].time) - 26,
                  width: axisX - 24,
                  child: _ExtremeCard(
                    extreme: extremes[i],
                    deltaCm: i == 0
                        ? null
                        : extremes[i].heightCm - extremes[i - 1].heightCm,
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
  const _ExtremeCard({required this.extreme, required this.deltaCm});

  final TideExtreme extreme;
  final double? deltaCm;

  @override
  Widget build(BuildContext context) {
    final isHigh = extreme.isHigh;
    final bg = isHigh ? const Color(0xFFB0334A) : const Color(0xFF29508C);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
