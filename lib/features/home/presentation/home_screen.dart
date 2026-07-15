import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/mul_ttae.dart';
import '../../locations/presentation/providers.dart';
import '../../tide/presentation/providers.dart';
import '../../weather/presentation/providers.dart';
import '../../weather/presentation/widgets/wind_arrow.dart';

/// 홈 대시보드: 선택 지역의 오늘 물때 + 다음 만조/간조 + 현재 해양 날씨 요약.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(selectedLocationProvider);
    final now = DateTime.now();
    // provider family 키는 값이 매 빌드 동일해야 하므로 날짜 단위로 정규화한다.
    final today = DateUtils.dateOnly(now);
    final tideAsync = ref.watch(
      tideDayProvider((location: location, date: today)),
    );
    final forecastAsync = ref.watch(marineForecastProvider(location));
    final mulTtae = mulTtaeFor(
      now,
      system: mulTtaeSystemForRegion(location.region),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('바다모바일')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${location.name} · ${formatMonthDay(now)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            '오늘은 ${mulTtae.label}입니다 (음력 ${mulTtae.lunarDay}일'
            '${mulTtae.isSari
                ? ' · 사리'
                : mulTtae.isJogeum
                ? ' · 소조기'
                : ''})',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          tideAsync.when(
            loading: () => const _LoadingCard(),
            error: (e, _) => _ErrorCard(message: '조석 정보 오류: $e'),
            data: (tide) {
              final next = tide.nextExtremeAfter(now);
              return Card(
                child: ListTile(
                  leading: Icon(
                    next == null
                        ? Icons.nightlight_outlined
                        : next.isHigh
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    color: next?.isHigh == true
                        ? Colors.redAccent
                        : Colors.blueAccent,
                  ),
                  title: Text(
                    next == null
                        ? '오늘 남은 만조/간조가 없습니다'
                        : '다음 ${next.isHigh ? '만조' : '간조'}',
                  ),
                  subtitle: next == null
                      ? null
                      : Text(
                          '${formatHm(next.time)} · ${formatTideHeight(next.heightCm)}',
                        ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          forecastAsync.when(
            loading: () => const _LoadingCard(),
            error: (e, _) => _ErrorCard(message: '날씨 정보 오류: $e'),
            data: (forecast) {
              final current = forecast.current;
              return Card(
                child: ListTile(
                  leading: WindArrow(
                    directionDeg: current.windDirectionDeg,
                    size: 24,
                  ),
                  title: Text(
                    '${compassKo(current.windDirectionDeg)}풍 '
                    '${formatWind(current.windSpeedMs)} · '
                    '파고 ${formatWave(current.waveHeightM)} '
                    '(${formatPeriod(current.wavePeriodS)})',
                  ),
                  subtitle: Text(
                    '수온 ${current.waterTempC.toStringAsFixed(1)}° · '
                    '기온 ${current.airTempC.toStringAsFixed(1)}°',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            '하단 탭에서 상세 물때표와 시간별 해양 날씨를 확인하세요.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: SizedBox(
        height: 72,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
    );
  }
}
