import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/mul_ttae.dart';
import '../../home/presentation/home_screen.dart';
import '../../kma_weather/presentation/kma_weather_screen.dart';
import '../../locations/presentation/providers.dart';
import '../../locations/presentation/widgets/region_selector_action.dart';
import '../../settings/presentation/providers.dart';
import '../data/models/tide_data.dart';
import 'providers.dart';
import 'widgets/moon_phase_icon.dart';
import 'widgets/mul_ttae_calendar.dart';
import 'widgets/tide_chart.dart';
import 'widgets/tide_timeline.dart';

/// 물때 & 날씨 화면 — 앱의 메인 탭.
///
/// 한 화면(스크롤 없음) 구성:
/// - 상단: 날짜(탭하면 연/월 이동 팝업=물때달력) + 5일 선택 스트립(◀◀/▶▶는
///   5일 단위 이동)
/// - 가운데: 조류세기(라벨+%) + 만조·간조 타임라인(사진풍 바다 배경) +
///   오른쪽 세로 메뉴(낚시정보·날씨·물때달력·조위그래프)
/// - 하단: 광고 자리(현재는 앱 소개 박스)
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

  DateTime _clamp(DateTime d) {
    if (d.isBefore(_minDate)) return _minDate;
    if (d.isAfter(_maxDate)) return _maxDate;
    return d;
  }

  void _select(DateTime d) => setState(() => _date = _clamp(d));

  Future<void> _openCalendar() async {
    final system = mulTtaeSystemForRegion(
      ref.read(selectedLocationProvider).region,
    );
    final picked = await showMulTtaeCalendar(
      context,
      initial: _date,
      minDate: _minDate,
      maxDate: _maxDate,
      system: system,
    );
    if (picked != null) _select(picked);
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(selectedLocationProvider);
    final system = mulTtaeSystemForRegion(location.region);
    final mulTtae = mulTtaeFor(_date, system: system);
    final isToday = DateUtils.isSameDay(_date, DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('물때 & 날씨'),
        actions: const [RegionSelectorAction()],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DateHeader(date: _date, mulTtae: mulTtae, onTap: _openCalendar),
              const SizedBox(height: 6),
              _FiveDayStrip(
                date: _date,
                minDate: _minDate,
                maxDate: _maxDate,
                system: system,
                onSelect: _select,
                onSelectedTap: _openCalendar,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _tideAvailable
                    ? _TideBody(
                        query: (location: location, date: _date),
                        isToday: isToday,
                        onOpenCalendar: _openCalendar,
                      )
                    : _OutOfRangeCard(mulTtae: mulTtae),
              ),
              const SizedBox(height: 8),
              const _AdPlaceholder(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 상단 한 줄 날짜 헤더. 탭하면 연/월을 바꾸는 물때달력 팝업이 뜬다.
class _DateHeader extends StatelessWidget {
  const _DateHeader({
    required this.date,
    required this.mulTtae,
    required this.onTap,
  });

  final DateTime date;
  final MulTtae mulTtae;
  final VoidCallback onTap;

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final suffix = mulTtae.isSari
        ? ' · 사리'
        : mulTtae.isJogeum
        ? ' · 소조기'
        : '';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MoonPhaseIcon(date: date, size: 20),
            const SizedBox(width: 8),
            Text(
              '${date.year}.${date.month}.${date.day} '
              '(${_weekdays[date.weekday - 1]}) · '
              '음력 ${mulTtae.lunarDay}일 ${mulTtae.label}$suffix',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}

/// 선택일 상하 2일씩, 총 5일을 보여주는 날짜 선택 스트립.
/// 좌우 끝의 쌍삼각형(◀◀/▶▶) 버튼은 5일 전체를 한 번에 이동한다.
class _FiveDayStrip extends StatelessWidget {
  const _FiveDayStrip({
    required this.date,
    required this.minDate,
    required this.maxDate,
    required this.system,
    required this.onSelect,
    required this.onSelectedTap,
  });

  final DateTime date;
  final DateTime minDate;
  final DateTime maxDate;
  final MulTtaeSystem system;
  final ValueChanged<DateTime> onSelect;

  /// 이미 선택된 날짜를 다시 탭했을 때(연/월 팝업 열기).
  final VoidCallback onSelectedTap;

  @override
  Widget build(BuildContext context) {
    final days = [for (var i = -2; i <= 2; i++) date.add(Duration(days: i))];
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: date.isAfter(minDate)
              ? () => onSelect(date.subtract(const Duration(days: 5)))
              : null,
          icon: const Icon(Icons.keyboard_double_arrow_left),
          tooltip: '5일 이전',
        ),
        Expanded(
          child: Row(
            children: [
              for (final d in days)
                Expanded(
                  child: _DayChip(
                    date: d,
                    selected: DateUtils.isSameDay(d, date),
                    enabled: !d.isBefore(minDate) && !d.isAfter(maxDate),
                    isToday: DateUtils.isSameDay(d, DateTime.now()),
                    system: system,
                    onTap: DateUtils.isSameDay(d, date)
                        ? onSelectedTap
                        : () => onSelect(d),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: date.isBefore(maxDate)
              ? () => onSelect(date.add(const Duration(days: 5)))
              : null,
          icon: const Icon(Icons.keyboard_double_arrow_right),
          tooltip: '5일 이후',
        ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.date,
    required this.selected,
    required this.enabled,
    required this.isToday,
    required this.system,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool enabled;
  final bool isToday;
  final MulTtaeSystem system;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mt = mulTtaeFor(date, system: system);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerLow.withValues(alpha: enabled ? 1 : 0.5),
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(color: scheme.primary)
              : isToday
              ? Border.all(color: scheme.outlineVariant)
              : null,
        ),
        child: Column(
          children: [
            Text(
              '${date.month}/${date.day}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: enabled
                    ? null
                    : scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              mt.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: selected ? FontWeight.bold : null,
                color: !enabled
                    ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
                    : mt.isSari
                    ? scheme.error
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 조석 데이터 본문: 조류세기 + (타임라인 | 오른쪽 메뉴).
class _TideBody extends ConsumerWidget {
  const _TideBody({
    required this.query,
    required this.isToday,
    required this.onOpenCalendar,
  });

  final TideQuery query;
  final bool isToday;
  final VoidCallback onOpenCalendar;

  /// 하루 조위 변화폭 기준의 정성적 조류세기(0~1, 라벨).
  (double, String) _strength(List<double> hourlyHeightsCm) {
    if (hourlyHeightsCm.isEmpty) return (0, '보통');
    final maxV = hourlyHeightsCm.reduce((a, b) => a > b ? a : b);
    final minV = hourlyHeightsCm.reduce((a, b) => a < b ? a : b);
    // 대략적인 대조기 조차(~800cm)를 상한으로 정규화한다.
    final fraction = ((maxV - minV) / 800).clamp(0.0, 1.0);
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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('조석 정보를 불러오지 못했습니다: $e')),
      data: (tide) {
        final (fraction, label) = _strength(tide.hourlyHeightsCm);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D2C47),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TideCurrentStrengthBar(fraction: fraction, label: label),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 타임라인은 가로를 줄이고(오른쪽 메뉴 공간), 세로는 남은
                  // 공간을 모두 채워 스크롤 없이 한 화면에 들어간다.
                  Expanded(
                    child: TideTimeline(
                      extremes: tide.extremes,
                      now: isToday ? DateTime.now() : null,
                      showBackdrop: ref.watch(backdropEnabledProvider),
                      height: null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _RightMenu(tide: tide, onOpenCalendar: onOpenCalendar),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 오른쪽 세로 메뉴 — 하단 탭에 있던 항목들을 이쪽으로 옮겼다.
class _RightMenu extends StatelessWidget {
  const _RightMenu({required this.tide, required this.onOpenCalendar});

  final TideDay tide;
  final VoidCallback onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget item(IconData icon, String label, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              children: [
                Icon(icon, size: 22, color: scheme.primary),
                const SizedBox(height: 4),
                Text(label, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ),
      );
    }

    // 세로 공간이 모자란 소형 화면에서도 넘치지 않게 스크롤을 허용한다.
    return SingleChildScrollView(
      child: Column(
        children: [
          item(Icons.phishing, '낚시정보', () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const HomeScreen()));
          }),
          item(Icons.wb_sunny_outlined, '날씨', () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const KmaWeatherScreen()));
          }),
          item(Icons.calendar_month_outlined, '물때달력', onOpenCalendar),
          item(Icons.show_chart, '조위그래프', () {
            showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '상세 조위 그래프',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TideChart(
                        hourlyHeightsCm: tide.hourlyHeightsCm,
                        now: DateUtils.isSameDay(tide.date, DateTime.now())
                            ? DateTime.now()
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// 조석 제공 범위(±1년)를 벗어난 날짜 안내(물때 배지는 상단에 이미 표시).
class _OutOfRangeCard extends StatelessWidget {
  const _OutOfRangeCard({required this.mulTtae});

  final MulTtae mulTtae;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 32),
              const SizedBox(height: 8),
              Text(
                '조석(만조/간조·조위) 예보는 오늘 기준 1년 이내만 제공됩니다.\n'
                '이 날짜는 물때(${mulTtae.label}) 정보만 확인할 수 있습니다 (최대 2년).',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 하단 광고 자리. 광고를 붙이기 전까지는 같은 크기의 박스에 앱 아이콘과
/// 짧은 소개를 담아 둔다(추후 이 위젯만 광고 위젯으로 교체).
class _AdPlaceholder extends StatelessWidget {
  const _AdPlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/icon/app_icon.png',
              width: 36,
              height: 36,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.waves, size: 32, color: scheme.primary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '바다윈디',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  '물때·날씨·바람을 한눈에 보는 낚시 도우미',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
