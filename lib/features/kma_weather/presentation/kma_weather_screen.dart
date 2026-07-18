import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../locations/presentation/providers.dart';
import '../../locations/presentation/widgets/region_selector_action.dart';
import '../data/models/kma_forecast.dart';
import 'providers.dart';

/// 날씨 예보 화면: 기상청 단기예보(육상) 기반 일자별/시간별 예보.
/// Windy 탭(해양·바람 지도)과는 별개로, 기온·하늘상태·강수확률 위주로 보여준다.
class KmaWeatherScreen extends ConsumerStatefulWidget {
  const KmaWeatherScreen({super.key});

  @override
  ConsumerState<KmaWeatherScreen> createState() => _KmaWeatherScreenState();
}

class _KmaWeatherScreenState extends ConsumerState<KmaWeatherScreen> {
  int _selectedDay = 0;

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(selectedLocationProvider);
    final forecastAsync = ref.watch(kmaForecastProvider(location));

    return Scaffold(
      appBar: AppBar(
        title: const Text('날씨 예보'),
        actions: const [RegionSelectorAction()],
      ),
      body: forecastAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('날씨 예보를 불러오지 못했습니다: $e')),
        data: (forecast) {
          final days = forecast.dailySummaries;
          if (days.isEmpty) {
            return const Center(child: Text('예보 데이터가 없습니다.'));
          }
          final dayIndex = _selectedDay.clamp(0, days.length - 1);
          final selectedDay = days[dayIndex];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                location.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '기상청 단기예보 기준(육상)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 108,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: days.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final day = days[i];
                    final isSelected = i == dayIndex;
                    final rep = day.representative;
                    return _DayCard(
                      day: day.date,
                      isSelected: isSelected,
                      minTempC: day.minTempC,
                      maxTempC: day.maxTempC,
                      popPercent: day.maxPopPercent,
                      conditionLabel: rep.ptyCode != 0
                          ? ptyLabelKo(rep.ptyCode)
                          : skyLabelKo(rep.skyCode),
                      onTap: () => setState(() => _selectedDay = i),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text('시간별 예보', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              for (final h in selectedDay.hourly) _HourlyRow(hourly: h),
            ],
          );
        },
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.isSelected,
    required this.minTempC,
    required this.maxTempC,
    required this.popPercent,
    required this.conditionLabel,
    required this.onTap,
  });

  final DateTime day;
  final bool isSelected;
  final double minTempC;
  final double maxTempC;
  final int popPercent;
  final String conditionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 88,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                formatMonthDay(day),
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              Text(
                conditionLabel,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(
                '${minTempC.round()}° / ${maxTempC.round()}°',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                '강수 $popPercent%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HourlyRow extends StatelessWidget {
  const _HourlyRow({required this.hourly});

  final KmaHourly hourly;

  @override
  Widget build(BuildContext context) {
    final condition = hourly.ptyCode != 0
        ? ptyLabelKo(hourly.ptyCode)
        : skyLabelKo(hourly.skyCode);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(width: 44, child: Text(formatHm(hourly.time))),
      title: Text(condition),
      subtitle: Text(
        '강수확률 ${hourly.popPercent}% · 습도 ${hourly.humidityPercent}%',
      ),
      trailing: Text(
        '${hourly.tempC.round()}°',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
