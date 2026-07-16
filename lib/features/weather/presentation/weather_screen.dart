import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../locations/presentation/providers.dart';
import '../data/models/marine_weather.dart';
import 'providers.dart';
import 'widgets/wind_arrow.dart';
import 'wind_map_screen.dart';

/// 바람·해양 날씨 화면 (윈디 영역). 16일치 시간별 예보를 날짜별로 묶어 보여준다.
class WeatherScreen extends ConsumerWidget {
  const WeatherScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(selectedLocationProvider);
    final forecastAsync = ref.watch(marineForecastProvider(location));

    return Scaffold(
      appBar: AppBar(title: Text('해양 날씨 · ${location.name}')),
      body: forecastAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('예보를 불러오지 못했습니다: $e')),
        data: (forecast) => _ForecastList(forecast: forecast),
      ),
    );
  }
}

/// 리스트 항목: 날짜 헤더 또는 시간별 행.
typedef _Item = ({DateTime? dayHeader, HourlyMarine? hour});

class _ForecastList extends StatelessWidget {
  const _ForecastList({required this.forecast});

  final MarineForecast forecast;

  List<_Item> _buildItems() {
    final items = <_Item>[];
    DateTime? currentDay;
    for (final h in forecast.hourly) {
      final day = DateUtils.dateOnly(h.time);
      if (currentDay == null || day != currentDay) {
        currentDay = day;
        items.add((dayHeader: day, hour: null));
      }
      // 첫 48시간은 매시간, 이후는 3시간 간격으로 표시해 목록을 가볍게 유지.
      final hoursFromStart = h.time.difference(forecast.hourly.first.time);
      if (hoursFromStart <= const Duration(hours: 48) || h.time.hour % 3 == 0) {
        items.add((dayHeader: null, hour: h));
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems();
    final now = forecast.current;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _Header(now: now, days: forecast.forecastDays);
        }
        final item = items[index - 1];
        if (item.dayHeader != null) {
          return Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              formatMonthDay(item.dayHeader!),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          );
        }
        final h = item.hour!;
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: SizedBox(width: 44, child: Text(formatHm(h.time))),
          title: Row(
            children: [
              WindArrow(directionDeg: h.windDirectionDeg, size: 16),
              const SizedBox(width: 4),
              SizedBox(width: 64, child: Text(formatWind(h.windSpeedMs))),
              Icon(
                Icons.waves,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '${formatWave(h.waveHeightM)} ${formatPeriod(h.wavePeriodS)}',
              ),
            ],
          ),
          trailing: Text('${h.airTempC.toStringAsFixed(0)}°'),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.now, required this.days});

  final HourlyMarine now;
  final int days;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _SummaryItem(
                  icon: WindArrow(directionDeg: now.windDirectionDeg, size: 28),
                  value: formatWind(now.windSpeedMs),
                  label:
                      '${compassKo(now.windDirectionDeg)}풍 · '
                      '돌풍 ${formatWind(now.windGustMs)}',
                ),
                _SummaryItem(
                  icon: const Icon(Icons.waves, size: 28),
                  value:
                      '${formatWave(now.waveHeightM)} ${formatPeriod(now.wavePeriodS)}',
                  label: '파고 · 주기 (${compassKo(now.waveDirectionDeg)}향)',
                ),
                _SummaryItem(
                  icon: const Icon(Icons.thermostat, size: 28),
                  value: '${now.waterTempC.toStringAsFixed(1)}°',
                  label: '수온',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const WindMapScreen())),
            child: Container(
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(context).colorScheme.surfaceContainerHigh,
                  ],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.map_outlined, size: 32),
                  const SizedBox(height: 6),
                  Text(
                    '바람 지도 (윈디 스타일) — 탭하여 보기',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('$days일 예보', style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final Widget icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          icon,
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
