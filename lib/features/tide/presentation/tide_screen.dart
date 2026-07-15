import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/mul_ttae.dart';
import '../../locations/presentation/providers.dart';
import 'providers.dart';
import 'widgets/tide_chart.dart';

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
      appBar: AppBar(title: Text('물때 · ${location.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _date.isAfter(_minDate)
                    ? () => setState(
                        () => _date = _date.subtract(const Duration(days: 1)),
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
          if (!_tideAvailable)
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
            )
          else
            _TideBody(
              query: (location: location, date: _date),
              isToday: isToday,
            ),
        ],
      ),
    );
  }
}

class _TideBody extends ConsumerWidget {
  const _TideBody({required this.query, required this.isToday});

  final TideQuery query;
  final bool isToday;

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
      data: (tide) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: TideChart(
                hourlyHeightsCm: tide.hourlyHeightsCm,
                now: isToday ? DateTime.now() : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...tide.extremes.map(
            (e) => Card(
              child: ListTile(
                leading: Icon(
                  e.isHigh ? Icons.arrow_upward : Icons.arrow_downward,
                  color: e.isHigh ? Colors.redAccent : Colors.blueAccent,
                ),
                title: Text(e.isHigh ? '만조' : '간조'),
                trailing: Text(
                  '${formatHm(e.time)}  ·  ${formatTideHeight(e.heightCm)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ),
        ],
      ),
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
