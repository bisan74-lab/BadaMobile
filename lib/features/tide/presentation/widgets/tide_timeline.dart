import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/sea_backdrop.dart';
import '../../data/models/tide_data.dart';

/// 만조/간조를 세로 0~24시 타임라인 위에 그래픽 카드로 배치해 보여준다.
/// 하루의 조석 흐름을 시간축 위에 배치하는 통상적인 물때표 형식으로,
/// 바다색 배경 위에 시각축과 만조(붉은색)/간조(파란색) 카드, 현재
/// 시각선을 함께 그린다.
class TideTimeline extends StatelessWidget {
  const TideTimeline({
    super.key,
    required this.extremes,
    required this.now,
    this.showBackdrop = true,
    this.height = 512,
    this.frameless = false,
  });

  final List<TideExtreme> extremes;
  final DateTime? now;

  /// 바다 배경(사진풍 이미지) 표시 여부(설정 > 템플릿 > 배경 그래픽).
  final bool showBackdrop;

  /// 타임라인 높이. null이면 부모 제약(예: Expanded)을 그대로 채운다 —
  /// 물때&날씨 화면이 스크롤 없이 한 화면에 들어가게 할 때 쓴다.
  final double? height;

  /// true면 자체 배경(박스 색·바다 이미지)을 그리지 않는다 — 화면 전체가
  /// 이미 바다 배경일 때(물때&날씨 전체화면 배경) 이중 배경을 피한다.
  final bool frameless;

  /// 만조는 축 왼쪽, 간조는 축 오른쪽에 배치해 양쪽 공간을 고르게 쓴다.
  static const double _axisFraction = 0.5;

  /// 축(세로선)과 카드 사이 간격 — 카드가 세로선·시각 라벨을 가리지 않도록
  /// 넉넉히 띄운다.
  static const double _cardGap = 26;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: frameless ? Colors.transparent : const Color(0xFF082238),
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
              // 사진풍 바다 배경(절차적으로 생성한 자체 이미지 — 라이선스 없음).
              // 카드·라벨 가독성을 위해 어두운 그라디언트를 살짝 덮는다.
              if (showBackdrop && !frameless) ...[
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/sea_photo_bg.jpg',
                    fit: BoxFit.cover,
                    // 테스트 등 에셋을 못 읽는 환경에선 기존 그린 배경으로.
                    errorBuilder: (_, _, _) => const SeaBackdrop(opacity: 0.9),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.18),
                          Colors.black.withValues(alpha: 0.30),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
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
              // 시각 라벨(0/6/12/18/24시)은 맨 위 레이어로 그려 카드·점에
              // 가리지 않게 한다.
              for (final h in const [0, 6, 12, 18, 24])
                Positioned(
                  left: axisX - 22,
                  top: yForMinutes(h * 60) - 10,
                  child: Container(
                    width: 44,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B2A46),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white38),
                      boxShadow: const [
                        BoxShadow(color: Colors.black45, blurRadius: 3),
                      ],
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
            // 정성 라벨(강함 등)과 비율(%)을 함께 보여준다(사용자 요청).
            '$label ${(f * 100).round()}%',
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
