import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/mul_ttae.dart';
import '../../fishing/data/models/fishing_index.dart';
import '../../fishing/presentation/providers.dart';
import '../../locations/presentation/providers.dart';
import '../../locations/presentation/widgets/region_selector_action.dart';
import '../../tide/presentation/providers.dart';
import '../../weather/data/models/marine_weather.dart';
import '../../weather/presentation/providers.dart';
import '../../weather/presentation/widgets/wind_arrow.dart';
import 'widgets/fishing_level_badge.dart';
import 'widgets/home_date_strip.dart';

/// 홈 대시보드: 선택 지역의 물때 + 만조/간조 + 해양 날씨 + 낚시지수 요약.
/// 상단 날짜 띠로 과거 2주~미래 2주(4주) 범위를 좌우로 넘기며 볼 수 있다.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  DateTime _date = DateUtils.dateOnly(DateTime.now());

  DateTime get _today => DateUtils.dateOnly(DateTime.now());
  DateTime get _minDate =>
      _today.subtract(const Duration(days: homeForecastPastDays));
  DateTime get _maxDate =>
      _today.add(const Duration(days: homeForecastFutureDays - 1));

  /// [forecast]에서 [date]를 대표할 시간별 값을 고른다.
  /// 오늘이면 지금 시각에 가장 가까운 값, 아니면 그날 정오에 가장 가까운 값.
  HourlyMarine? _representativeHourly(MarineForecast forecast, DateTime date) {
    final target = DateUtils.isSameDay(date, DateTime.now())
        ? DateTime.now()
        : DateTime(date.year, date.month, date.day, 12);
    HourlyMarine? best;
    Duration? bestDiff;
    for (final h in forecast.hourly) {
      if (!DateUtils.isSameDay(h.time, date)) continue;
      final diff = h.time.difference(target).abs();
      if (bestDiff == null || diff < bestDiff) {
        bestDiff = diff;
        best = h;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(selectedLocationProvider);
    final isToday = DateUtils.isSameDay(_date, DateTime.now());
    final mulTtae = mulTtaeFor(
      _date,
      system: mulTtaeSystemForRegion(location.region),
    );
    final tideAsync = ref.watch(
      tideDayProvider((location: location, date: _date)),
    );
    final forecastAsync = ref.watch(homeMarineForecastProvider(location));
    final fishingAsync = ref.watch(fishingForecastProvider(location));

    return Scaffold(
      appBar: AppBar(
        title: const Text('바다 윈디'),
        actions: const [RegionSelectorAction()],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E5C8A), Color(0xFF0E3454)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.place, color: Colors.white70, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      location.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      isToday ? '오늘' : formatMonthDay(_date),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${isToday ? '오늘' : '${formatMonthDay(_date)}은'}은 '
                  '${mulTtae.label}입니다 (음력 ${mulTtae.lunarDay}일'
                  '${mulTtae.isSari
                      ? ' · 사리'
                      : mulTtae.isJogeum
                      ? ' · 소조기'
                      : ''})',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                HomeDateStrip(
                  date: _date,
                  minDate: _minDate,
                  maxDate: _maxDate,
                  onChanged: (d) => setState(() => _date = d),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tideAsync.when(
                  loading: () => const _LoadingCard(),
                  error: (e, _) => _ErrorCard(message: '조석 정보 오류: $e'),
                  data: (tide) {
                    final extreme = isToday
                        ? tide.nextExtremeAfter(DateTime.now())
                        : (tide.extremes.isEmpty ? null : tide.extremes.first);
                    final highCount = tide.extremes
                        .where((e) => e.isHigh)
                        .length;
                    final lowCount = tide.extremes.length - highCount;
                    return _InfoCard(
                      color: extreme?.isHigh == true
                          ? const Color(0xFFB0334A)
                          : const Color(0xFF29508C),
                      icon: extreme == null
                          ? Icons.nightlight_outlined
                          : extreme.isHigh
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      title: Text(
                        extreme == null
                            ? (isToday ? '오늘 남은 만조/간조가 없습니다' : '만조/간조 정보가 없습니다')
                            : isToday
                            ? '다음 ${extreme.isHigh ? '만조' : '간조'}'
                            : '${formatMonthDay(_date)} 첫 ${extreme.isHigh ? '만조' : '간조'}',
                      ),
                      subtitle: extreme == null
                          ? null
                          : Text(
                              '${formatHm(extreme.time)} · ${formatTideHeight(extreme.heightCm)}'
                              ' · 만조 $highCount회 · 간조 $lowCount회',
                            ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                forecastAsync.when(
                  loading: () => const _LoadingCard(),
                  error: (e, _) => _ErrorCard(message: '날씨 정보 오류: $e'),
                  data: (forecast) {
                    final at = _representativeHourly(forecast, _date);
                    if (at == null) {
                      return const _InfoCard(
                        color: Color(0xFF2C7A9C),
                        icon: Icons.cloud_off_outlined,
                        title: Text('선택한 날짜의 날씨 정보가 없습니다'),
                      );
                    }
                    return _InfoCard(
                      color: const Color(0xFF2C7A9C),
                      leading: WindArrow(
                        directionDeg: at.windDirectionDeg,
                        size: 24,
                        color: Colors.white,
                      ),
                      title: Text(
                        '${compassKo(at.windDirectionDeg)}풍 '
                        '${formatWind(at.windSpeedMs)} · '
                        '파고 ${formatWave(at.waveHeightM)} '
                        '(${formatPeriod(at.wavePeriodS)})',
                      ),
                      subtitle: Text(
                        '수온 ${at.waterTempC.toStringAsFixed(1)}° · '
                        '기온 ${at.airTempC.toStringAsFixed(1)}°'
                        '${isToday ? '' : ' · ${formatHm(at.time)} 기준'}',
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                fishingAsync.when(
                  loading: () => const _LoadingCard(),
                  error: (e, _) => _ErrorCard(message: '낚시지수 오류: $e'),
                  data: (fishing) {
                    final groups = fishing.speciesGroupsForDate(
                      _date,
                      preferredSpecies: preferredSpeciesForRegion(
                        location.region,
                      ),
                    );
                    if (groups.isEmpty) {
                      return const _InfoCard(
                        color: Color(0xFF4C9BC9),
                        icon: Icons.phishing,
                        title: Text('선택한 날짜의 낚시지수 정보가 없습니다'),
                      );
                    }
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '바다낚시지수',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            for (final indices in groups) ...[
                              const SizedBox(height: 8),
                              if (indices.first.species != null)
                                Text(
                                  '기준 어종 ${indices.first.species}',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  for (final index in indices) ...[
                                    FishingLevelBadge(
                                      timeSlot: index.timeSlot,
                                      grade: index.grade,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                ],
                              ),
                            ],
                          ],
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
          ),
        ],
      ),
    );
  }
}

/// 색상 아이콘 + 제목/부제를 가진 요약 카드 (물때/날씨 공용).
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.color,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
  }) : assert(icon != null || leading != null);

  final Color color;
  final IconData? icon;
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          child: leading ?? Icon(icon, color: Colors.white),
        ),
        title: title,
        subtitle: subtitle,
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
