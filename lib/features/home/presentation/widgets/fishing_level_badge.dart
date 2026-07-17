import 'package:flutter/material.dart';

import '../../../fishing/data/models/fishing_index.dart';

/// 낚시지수 등급별 색상 — 차가움(매우나쁨) → 따뜻함(매우좋음) 순으로
/// 파랑~초록~주황~빨강 스케일을 쓴다.
Color fishingGradeColor(FishingGrade grade) => switch (grade) {
  FishingGrade.veryBad => const Color(0xFF5B7FA6),
  FishingGrade.bad => const Color(0xFF4C9BC9),
  FishingGrade.normal => const Color(0xFF4CAF7D),
  FishingGrade.good => const Color(0xFFE0A23A),
  FishingGrade.veryGood => const Color(0xFFD1583A),
};

/// 시간대별 낚시지수를 카드형 배지로 보여준다.
///
/// 예전엔 노란 점 5개로 표시했는데, 가로로 늘어선 점 모양이 스와이프
/// 인디케이터처럼 보인다는 피드백을 반영해 등급색 배지 + 채움 막대로
/// 바꿨다(점·노란색 단일색 지양).
class FishingLevelBadge extends StatelessWidget {
  const FishingLevelBadge({
    super.key,
    required this.timeSlot,
    required this.grade,
  });

  final String timeSlot;
  final FishingGrade grade;

  @override
  Widget build(BuildContext context) {
    final color = fishingGradeColor(grade);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            timeSlot,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.set_meal, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                grade.label,
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              width: 76,
              height: 5,
              child: Stack(
                children: [
                  Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                  FractionallySizedBox(
                    widthFactor: grade.score / FishingGrade.values.length,
                    child: Container(color: color),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
