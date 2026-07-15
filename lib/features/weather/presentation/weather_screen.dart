import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../locations/presentation/providers.dart';
import 'providers.dart';
import 'widgets/wind_arrow.dart';

/// 바람·해양 날씨 화면 (윈디 영역).
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
        data: (forecast) {
          final now = forecast.current;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 현재 요약 카드
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _SummaryItem(
                        icon: WindArrow(
                          directionDeg: now.windDirectionDeg,
                          size: 28,
                        ),
                        value: formatWind(now.windSpeedMs),
                        label: '${compassKo(now.windDirectionDeg)}풍',
                      ),
                      _SummaryItem(
                        icon: const Icon(Icons.waves, size: 28),
                        value: formatWave(now.waveHeightM),
                        label: '파고',
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
              // 바람 지도 자리 (2단계 과제)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Container(
                  height: 140,
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
                      const Icon(Icons.map_outlined, size: 36),
                      const SizedBox(height: 8),
                      Text(
                        '바람 지도 (윈디 스타일) — 준비 중',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('시간별 예보', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...forecast.hourly
                  .take(24)
                  .map(
                    (h) => ListTile(
                      dense: true,
                      leading: SizedBox(
                        width: 48,
                        child: Text(formatHm(h.time)),
                      ),
                      title: Row(
                        children: [
                          WindArrow(directionDeg: h.windDirectionDeg, size: 16),
                          const SizedBox(width: 6),
                          Text(formatWind(h.windSpeedMs)),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.waves,
                            size: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(formatWave(h.waveHeightM)),
                        ],
                      ),
                      trailing: Text('${h.airTempC.toStringAsFixed(0)}°'),
                    ),
                  ),
            ],
          );
        },
      ),
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
    return Column(
      children: [
        icon,
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
