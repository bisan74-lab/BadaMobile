import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/mul_ttae.dart';
import '../../fishing/data/models/fishing_index.dart';
import '../../fishing/data/models/jigging_estimate.dart';
import '../../fishing/presentation/providers.dart';
import '../../locations/presentation/providers.dart';
import '../../locations/presentation/widgets/region_selector_action.dart';
import '../../tide/data/models/tide_data.dart';
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

  /// 관측 지수가 없는 어종(쭈꾸미·갑오징어·문어)의 추정 등급.
  ///
  /// 이미 화면에 있는 값만 쓴다 — 그날 조위(조류 세기)와 지점 예보의 바람·
  /// 파고. 조위나 예보를 아직 못 받았으면 null(행이 안 뜬다).
  List<JiggingEstimate>? _estimateFor(
    String species,
    TideDay? tide,
    MarineForecast? marine,
  ) {
    if (tide == null) return null;
    final strength = tideStrengthFraction(tide.hourlyHeightsCm);

    HourlyMarine? at(int hour) {
      if (marine == null) return null;
      final target = DateTime(_date.year, _date.month, _date.day, hour);
      HourlyMarine? best;
      var bestDiff = const Duration(days: 999);
      for (final h in marine.hourly) {
        final diff = h.time.difference(target).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          best = h;
        }
      }
      return best != null && DateUtils.isSameDay(best.time, _date)
          ? best
          : null;
    }

    JiggingEstimate one(String slot, HourlyMarine? h) => JiggingEstimate(
      species: species,
      timeSlot: slot,
      grade: estimateJiggingGrade(
        species: species,
        tideStrength: strength,
        windMs: h?.windSpeedMs ?? 0,
        gustMs: h?.windGustMs ?? 0,
        waveM: h?.waveHeightM ?? 0,
        month: _date.month,
      ),
    );

    return [one('오전', at(9)), one('오후', at(15))];
  }

  /// 대표 어종 변경 메뉴 — **이 지역에 값이 있는 어종** 중 하나를 골라
  /// [slot]에 반영한다.
  ///
  /// [available]은 이 지역 예보에 실제로 값이 있는 어종이다. 지수가 없는
  /// 어종을 고르면 화면이 빈칸으로 남으므로 목록에서 뺀다. 예보를 아직 못
  /// 받았으면(null) 후보 전체를 보여준다.
  Future<void> _pickSpecies(
    int slot,
    String current,
    Set<String>? available,
  ) async {
    final options = [
      for (final s in fishingSpeciesCatalog)
        if (available == null || available.contains(s)) s,
      // 추정 어종은 관측 데이터와 무관하게(물때·바람으로) 계산하므로 항상 뜬다.
      ...estimatedSpeciesCatalog,
    ];
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('대표 어종 선택', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (options.isEmpty) const Text('이 지역에는 어종별 지수가 없습니다.'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in options)
                    ChoiceChip(
                      label: Text(s),
                      selected: s == current,
                      onSelected: (_) => Navigator.of(context).pop(s),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) {
      ref.read(fishingSpeciesProvider.notifier).setAt(slot, chosen);
    }
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
    final species = ref.watch(fishingSpeciesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('바다윈디'),
        actions: const [RegionSelectorAction()],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: deepThemeColors(Theme.of(context).colorScheme),
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
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '바다낚시지수',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const Spacer(),
                                Text(
                                  '어종 탭하여 변경',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                            for (var slot = 0; slot < species.length; slot++)
                              _SpeciesRow(
                                species: species[slot],
                                indices: fishing
                                    .forDate(_date)
                                    .where((i) => i.species == species[slot])
                                    .toList(),
                                // 관측 지수가 없는 어종(쭈꾸미·갑오징어·문어)은
                                // 물때·바람으로 추정한 등급을 대신 보여준다.
                                estimated:
                                    estimatedSpeciesCatalog.contains(
                                      species[slot],
                                    )
                                    ? _estimateFor(
                                        species[slot],
                                        tideAsync.valueOrNull,
                                        forecastAsync.valueOrNull,
                                      )
                                    : null,
                                onTap: () => _pickSpecies(
                                  slot,
                                  species[slot],
                                  fishing.availableSpecies,
                                ),
                              ),
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

/// 대표 어종 한 줄: 어종명(탭하면 변경 메뉴) + 오전/오후 낚시지수 배지.
class _SpeciesRow extends StatelessWidget {
  const _SpeciesRow({
    required this.species,
    required this.indices,
    required this.onTap,
    this.estimated,
  });

  final String species;
  final List<FishingIndex> indices;

  /// 관측 지수가 없는 어종의 **추정** 등급(오전·오후). 있으면 [indices] 대신
  /// 이걸 보여주고 "추정" 배지를 단다 — 근거가 달라 구분해야 한다.
  final List<JiggingEstimate>? estimated;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sorted = [...indices]
      ..sort((a, b) => a.timeSlot.compareTo(b.timeSlot));
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '기준 어종 $species',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (estimated != null) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.outlineVariant),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '추정',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  Icon(Icons.arrow_drop_down, size: 20, color: scheme.primary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (estimated != null)
            Row(
              children: [
                for (final e in estimated!) ...[
                  FishingLevelBadge(timeSlot: e.timeSlot, grade: e.grade),
                  const SizedBox(width: 8),
                ],
              ],
            )
          else if (sorted.isEmpty)
            Text(
              '이 날짜의 지수 정보가 없습니다',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Row(
              children: [
                for (final index in sorted) ...[
                  FishingLevelBadge(
                    timeSlot: index.timeSlot,
                    grade: index.grade,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
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
