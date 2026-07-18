import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/mul_ttae.dart';
import '../../locations/presentation/providers.dart';
import '../../locations/presentation/widgets/region_selector_action.dart';
import '../../settings/presentation/providers.dart';
import 'providers.dart';
import 'widgets/moon_phase_icon.dart';
import 'widgets/tide_chart.dart';
import 'widgets/tide_date_picker.dart';
import 'widgets/tide_timeline.dart';

/// 조석·물때 화면 (바다타임 영역).
///
/// 제공 범위: 조석(그래프·만조/간조)은 오늘 기준 ±1년,
/// 단순 물때는 미래 2년까지 (그 구간에서는 물때 배지만 표시).
class TideScreen extends ConsumerStatefulWidget {
  const TideScreen({super.key});

  @override
  ConsumerState<TideScreen> createState() => _TideScreenState();
}

class _TideScreenState extends ConsumerState<TideScreen> {
  DateTime _date = DateUtils.dateOnly(DateTime.now());

  DateTime get _today => DateUtils.dateOnly(DateTime.now());
  DateTime get _minDate => _today.subtract(maxTideForecastRange);
  DateTime get _maxDate => _today.add(maxSimpleMulTtaeRange);
  bool get _tideAvailable =>
      !_date.isAfter(_today.add(maxTideForecastRange)) &&
      !_date.isBefore(_minDate);

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(selectedLocationProvider);
    final system = mulTtaeSystemForRegion(location.region);
    final mulTtae = mulTtaeFor(_date, system: system);
    final isToday = DateUtils.isSameDay(_date, DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('물때'),
        actions: const [RegionSelectorAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 연도 → 월 → 일 계층 날짜 선택기 (최대 2년 범위).
          TideDatePicker(
            date: _date,
            minDate: _minDate,
            maxDate: _maxDate,
            system: system,
            onChanged: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: 8),
          if (!_tideAvailable)
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _date.isAfter(_minDate)
                          ? () => setState(
                              () => _date = _date.subtract(
                                const Duration(days: 1),
                              ),
                            )
                          : null,
                    ),
                    Column(
                      children: [
                        Text(
                          formatMonthDay(_date),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        _MulTtaeBadge(mulTtae: mulTtae),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _date.isBefore(_maxDate)
                          ? () => setState(
                              () => _date = _date.add(const Duration(days: 1)),
                            )
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(Icons.info_outline, size: 32),
                        const SizedBox(height: 8),
                        Text(
                          '조석(만조/간조·조위) 예보는 오늘 기준 1년 이내만 제공됩니다.\n'
                          '이 날짜는 물때 정보만 확인할 수 있습니다 (최대 2년).',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          else
            _TideGraphicBody(
              query: (location: location, date: _date),
              date: _date,
              mulTtae: mulTtae,
              isToday: isToday,
              onPrevDay: _date.isAfter(_minDate)
                  ? () => setState(
                      () => _date = _date.subtract(const Duration(days: 1)),
                    )
                  : null,
              onNextDay: _date.isBefore(_maxDate)
                  ? () => setState(
                      () => _date = _date.add(const Duration(days: 1)),
                    )
                  : null,
              onToday: () => setState(() => _date = _today),
            ),
        ],
      ),
    );
  }
}

/// 그래픽 물때 화면 본문: 바다색 카드 위에 날짜·달 위상·물때 배지·조류세기,
/// 그 아래 세로 타임라인(만조/간조 카드)을 보여준다. 상세 조위 곡선은
/// 접이식으로 필요할 때만 펼친다.
class _TideGraphicBody extends ConsumerWidget {
  const _TideGraphicBody({
    required this.query,
    required this.date,
    required this.mulTtae,
    required this.isToday,
    required this.onPrevDay,
    required this.onNextDay,
    required this.onToday,
  });

  final TideQuery query;
  final DateTime date;
  final MulTtae mulTtae;
  final bool isToday;
  final VoidCallback? onPrevDay;
  final VoidCallback? onNextDay;
  final VoidCallback onToday;

  /// 하루 조위 변화폭 기준의 정성적 조류세기(0~1, 라벨).
  (double, String) _strength(List<double> hourlyHeightsCm) {
    if (hourlyHeightsCm.isEmpty) return (0, '보통');
    final maxV = hourlyHeightsCm.reduce((a, b) => a > b ? a : b);
    final minV = hourlyHeightsCm.reduce((a, b) => a < b ? a : b);
    final range = maxV - minV;
    // 대략적인 대조기 조차(~800cm)를 상한으로 정규화한다.
    final fraction = (range / 800).clamp(0.0, 1.0);
    final label = fraction >= 0.75
        ? '최대'
        : fraction >= 0.5
        ? '강함'
        : fraction >= 0.25
        ? '보통'
        : '약함';
    return (fraction, label);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tideAsync = ref.watch(tideDayProvider(query));
    return tideAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('조석 정보를 불러오지 못했습니다: $e'),
      ),
      data: (tide) {
        final (fraction, label) = _strength(tide.hourlyHeightsCm);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0E3454),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${date.year}년 ${formatMonthDay(date)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '음력 ${mulTtae.lunarDay}일 · ${mulTtae.label}'
                              '${mulTtae.isSari
                                  ? ' · 사리'
                                  : mulTtae.isJogeum
                                  ? ' · 소조기'
                                  : ''}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      MoonPhaseIcon(date: date, size: 34),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TideCurrentStrengthBar(fraction: fraction, label: label),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('상세 조위 그래프', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                child: TideChart(
                  hourlyHeightsCm: tide.hourlyHeightsCm,
                  now: isToday ? DateTime.now() : null,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: onPrevDay,
                  icon: const Icon(Icons.chevron_left, size: 18),
                  label: const Text('-1일'),
                ),
                TextButton(onPressed: onToday, child: const Text('오늘')),
                TextButton.icon(
                  onPressed: onNextDay,
                  icon: const Icon(Icons.chevron_right, size: 18),
                  label: const Text('+1일'),
                  iconAlignment: IconAlignment.end,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('만조·간조 타임라인', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            TideTimeline(
              extremes: tide.extremes,
              now: isToday ? DateTime.now() : null,
              showBackdrop: ref.watch(backdropEnabledProvider),
            ),
          ],
        );
      },
    );
  }
}

class _MulTtaeBadge extends StatelessWidget {
  const _MulTtaeBadge({required this.mulTtae});

  final MulTtae mulTtae;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = mulTtae.isSari
        ? (scheme.errorContainer, scheme.onErrorContainer)
        : mulTtae.isJogeum
        ? (scheme.surfaceContainerHighest, scheme.onSurfaceVariant)
        : (scheme.primaryContainer, scheme.onPrimaryContainer);
    final suffix = mulTtae.isSari
        ? ' · 사리'
        : mulTtae.isJogeum
        ? ' · 소조기'
        : '';
    final systemLabel = mulTtae.system == MulTtaeSystem.west7 ? '7물때식' : '8물때식';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '${mulTtae.label}$suffix (음력 ${mulTtae.lunarDay}일 · $systemLabel)',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
      ),
    );
  }
}
