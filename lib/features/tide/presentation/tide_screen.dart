import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../app/app.dart' show sideNavRailHeight;
import '../../../core/widgets/nav_chip.dart';
import '../../../core/utils/mul_ttae.dart';
import '../../../core/widgets/ad_placeholder.dart';
import '../../fishing/data/models/fishing_index.dart';
import '../../fishing/data/models/jigging_estimate.dart';
import '../../fishing/presentation/providers.dart';
import '../../kma_weather/data/weather_code.dart';
import '../../kma_weather/presentation/providers.dart';
import '../../kma_weather/presentation/widgets/weather_icon.dart';
import '../../locations/data/models/sea_location.dart';
import '../../locations/presentation/providers.dart';
import '../../locations/presentation/widgets/region_selector_action.dart';
import '../../settings/presentation/providers.dart';
import '../../weather/data/models/marine_weather.dart'
    show HourlyMarine, MarineForecast;
import '../../weather/presentation/providers.dart'
    show homeMarineForecastProvider;
import '../data/models/tide_data.dart';
import 'providers.dart';
import 'widgets/moon_phase_icon.dart';
import 'widgets/mul_ttae_calendar.dart';
import 'widgets/tide_chart.dart';
import 'widgets/tide_timeline.dart';

/// 중앙 패널 종류: 만조·간조 타임라인(기본)과 오른쪽 미니 메뉴로 전환하는
/// 낚시정보/날씨/물때달력/조위그래프. 메뉴를 누르면 새 화면이 아니라 그래프
/// 자리(중앙 영역)에 그대로 채워진다(사용자 요구).
enum _Panel { timeline, fishing, weather, calendar, chart }

/// 달별 제철 어종(낚시정보 기본값).
///
/// **[fishingSpeciesCatalog](관측)와 [estimatedSpeciesCatalog](추정) 안의
/// 어종만 쓴다** — 둘 중 어디에도 없는 어종을 넣으면 지수가 영영 빈칸으로
/// 남는다(테스트가 막는다). 가을엔 쭈꾸미·갑오징어가 제철이라 기본으로 넣는다.
List<String> seasonalSpecies(int month) => switch (month) {
  >= 3 && <= 5 => const ['참돔', '감성돔', '농어', '문어', '우럭'],
  >= 6 && <= 8 => const ['농어', '참돔', '우럭', '벵에돔', '돌돔'],
  >= 9 && <= 11 => const ['쭈꾸미', '갑오징어', '감성돔', '벵에돔', '문어'],
  _ => const ['우럭', '감성돔', '참돔', '문어', '농어'],
};

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
  _Panel _panel = _Panel.timeline;

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

    final showPhoto = ref.watch(backdropEnabledProvider);

    return Scaffold(
      // 바다 배경이 상태바·앱바 뒤까지 꽉 차게(전체화면 배경).
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFF0A2A44),
      appBar: AppBar(
        title: const Text('물때 & 날씨'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: const [RegionSelectorAction()],
      ),
      body: Stack(
        children: [
          // 전체화면 사진풍 바다 배경(설정 > 배경 사진에서 선택) + 가독성용
          // 어두운 그라디언트.
          if (showPhoto)
            Positioned.fill(
              child: Image.asset(
                ref.watch(backgroundImageProvider),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: Color(0xFF0A2A44)),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.black.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: 0.35),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              // 오른쪽은 앱 셸의 세로 탭 레일 공간을 살짝 비워 둔다.
              padding: const EdgeInsets.fromLTRB(12, 4, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 투명 앱바 높이만큼 내려서 시작.
                  SizedBox(height: kToolbarHeight - 8),
                  _DateHeader(
                    date: _date,
                    mulTtae: mulTtae,
                    onTap: _openCalendar,
                  ),
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
                            panel: _panel,
                            onPanel: (p) => setState(() => _panel = p),
                            minDate: _minDate,
                            maxDate: _maxDate,
                            system: system,
                            onPickDate: (d) {
                              _select(d);
                              setState(() => _panel = _Panel.timeline);
                            },
                          )
                        : _OutOfRangeCard(mulTtae: mulTtae),
                  ),
                  const SizedBox(height: 8),
                  const AdPlaceholder(slot: AdSlot.tide),
                ],
              ),
            ),
          ),
          // 오른쪽 미니 메뉴는 **화면 최상위 스택**에 둔다.
          //
          // 예전엔 본문 안쪽 스택에 넣고 "레일 자리만큼 아래를 비운다"를
          // 상수로 박아 뒀는데, 그 안쪽 스택의 바닥이 글자 배율에 따라
          // 움직여서 큰 글자에서 앱 탭 레일과 겹쳤다(2026-08-06 사용자 제보).
          // 지금은 탭 레일과 **같은 기준(화면 바닥)**으로 놓고 레일 바로 위에
          // 붙여, 계산이 어긋날 여지 자체를 없앤다.
          if (_tideAvailable)
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(
                  // 위쪽은 날짜 머리말을 침범하지 않을 만큼 비운다. 공간이
                  // 모자라면 메뉴가 이 안에서 스크롤된다.
                  top: kToolbarHeight + 120,
                  right: 6,
                  // 탭 레일(화면 바닥에서 88) 바로 위.
                  bottom: 88 + sideNavRailHeight(context) + 10,
                ),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: _MiniMenu(
                    key: const Key('tide_mini_menu'),
                    panel: _panel,
                    onPanel: (p) => setState(
                      () => _panel = _panel == p ? _Panel.timeline : p,
                    ),
                  ),
                ),
              ),
            ),
        ],
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
            // 시스템 글자 크기를 키우면 이 한 줄이 화면 폭을 넘긴다
            // (실측: 412px 폰 1.0배에서도 7px, 2.0배에서 133px 초과).
            // 날짜·물때는 잘라내면 안 되는 정보라 줄이는 대신 **줄바꿈**을
            // 허용하고, 남는 폭 안에서만 놓이도록 Flexible로 감싼다.
            Flexible(
              child: Text(
                '${date.year}.${date.month}.${date.day} '
                '(${_weekdays[date.weekday - 1]}) · '
                '음력 ${mulTtae.lunarDay}일 ${mulTtae.label}$suffix',
                textAlign: TextAlign.center,
                // 전체화면 바다 배경 위라 흰색 + 그림자로 가독성 확보.
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 20, color: Colors.white),
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

/// 조석 데이터 본문: 조류세기 + 중앙 패널(타임라인/낚시정보/날씨/달력/그래프)
/// + 오른쪽 미니 메뉴. 메뉴를 누르면 중앙 영역이 그 내용으로 채워진다.
class _TideBody extends ConsumerWidget {
  const _TideBody({
    required this.query,
    required this.isToday,
    required this.panel,
    required this.onPanel,
    required this.minDate,
    required this.maxDate,
    required this.system,
    required this.onPickDate,
  });

  final TideQuery query;
  final bool isToday;
  final _Panel panel;
  final ValueChanged<_Panel> onPanel;
  final DateTime minDate;
  final DateTime maxDate;
  final MulTtaeSystem system;
  final ValueChanged<DateTime> onPickDate;

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
              // 오른쪽 미니 메뉴 자리를 비운다 — 아래 패널([_PanelBox])과 **같은
              // 폭**이라 왼쪽 끝이 나란히 맞고, 메뉴 아이콘이 "강함 56%" 배지를
              // 덮지 않는다(2026-08-06 사용자 요구).
              margin: const EdgeInsets.only(right: 56),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TideCurrentStrengthBar(fraction: fraction, label: label),
            ),
            const SizedBox(height: 6),
            // 중앙 패널: 기본은 만조·간조 타임라인(가로 폭 축소), 미니 메뉴를
            // 누르면 같은 자리에 낚시정보/날씨/물때달력/조위그래프가 채워진다.
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: switch (panel) {
                      _Panel.timeline => Padding(
                        // 표(카드) 가로 길이를 줄인다 — 오른쪽 미니 메뉴
                        // 자리도 확보(사용자 요구).
                        padding: const EdgeInsets.only(left: 4, right: 56),
                        child: TideTimeline(
                          extremes: tide.extremes,
                          now: isToday ? DateTime.now() : null,
                          height: null,
                          frameless: true,
                        ),
                      ),
                      _Panel.fishing => _FishingPanel(
                        location: query.location,
                        date: query.date,
                        tide: tide,
                      ),
                      _Panel.weather => _WeatherPanel(
                        location: query.location,
                        date: query.date,
                      ),
                      _Panel.calendar => _CalendarPanel(
                        initial: query.date,
                        minDate: minDate,
                        maxDate: maxDate,
                        system: system,
                        onPicked: onPickDate,
                      ),
                      _Panel.chart => _ChartPanel(tide: tide, isToday: isToday),
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 그래프 오른쪽에 겹치는 반투명(55%) 미니 메뉴. 누르면 중앙 패널이 그
/// 내용으로 바뀐다. 맨 위 '물때'가 기본 화면(만조·간조 타임라인)으로
/// 돌아오는 명시적 버튼이다 — 다른 패널을 보다가 물때로 돌아오는 경로가
/// "켜진 버튼을 다시 누르기"뿐이면 어색하다는 사용자 지적으로 추가.
/// (활성 항목을 다시 눌러도 여전히 타임라인으로 돌아온다.)
///
/// 앱 탭 레일과 **같은 [NavChip]**을 쓴다 — 둘이 오른쪽 가장자리를 나눠 쓰므로
/// 배율에 따른 높이 변화를 같은 식으로 계산해야 겹치지 않는다.
class _MiniMenu extends StatelessWidget {
  const _MiniMenu({super.key, required this.panel, required this.onPanel});

  final _Panel panel;
  final ValueChanged<_Panel> onPanel;

  static const _items = <(_Panel, IconData, String)>[
    (_Panel.timeline, Icons.waves_outlined, '물때'),
    (_Panel.fishing, Icons.phishing, '낚시정보'),
    (_Panel.weather, Icons.wb_sunny_outlined, '날씨'),
    (_Panel.calendar, Icons.calendar_month_outlined, '물때달력'),
    (_Panel.chart, Icons.show_chart, '조위'),
  ];

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.55,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (p, icon, label) in _items)
              NavChip(
                icon: icon,
                label: label,
                selected: panel == p,
                onTap: () => onPanel(p),
              ),
          ],
        ),
      ),
    );
  }
}

/// 패널 공통 컨테이너: 반투명 어두운 배경(그래프 자리에 채워지는 카드).
class _PanelBox extends StatelessWidget {
  const _PanelBox({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 56),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 낚시정보 패널: 만조정보·바람정보와 낚시지수 두 블록만(날짜 없음).
/// 어종 기본값은 달별 제철 어종([seasonalSpecies]).
class _FishingPanel extends ConsumerWidget {
  const _FishingPanel({
    required this.location,
    required this.date,
    required this.tide,
  });

  final SeaLocation location;
  final DateTime date;
  final TideDay tide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marineAsync = ref.watch(homeMarineForecastProvider(location));
    final fishingAsync = ref.watch(fishingForecastProvider(location));
    // 사용자가 어종을 직접 골랐으면 그 목록을, 아니면 제철 어종을 쓴다.
    final custom = ref.watch(tideFishingSpeciesProvider);
    final chosen = custom.isNotEmpty ? custom : seasonalSpecies(date.month);
    // 관측 기반(API)과 추정(물때·바람)을 나눠서 다룬다.
    final species = [
      for (final s in chosen)
        if (!estimatedSpeciesCatalog.contains(s)) s,
    ];
    final estimated = _estimatesFor([
      for (final s in chosen)
        if (estimatedSpeciesCatalog.contains(s)) s,
    ], marineAsync.valueOrNull);

    String tideLine() {
      if (tide.extremes.isEmpty) return '정보 없음';
      return tide.extremes
          .map(
            (e) =>
                '${e.isHigh ? '만조' : '간조'} '
                '${e.time.hour.toString().padLeft(2, '0')}:'
                '${e.time.minute.toString().padLeft(2, '0')}',
          )
          .join('  ·  ');
    }

    return _PanelBox(
      title: '낚시정보',
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _InfoRow(icon: Icons.waves, label: '만조정보', value: tideLine()),
          const SizedBox(height: 8),
          marineAsync.when(
            loading: () => const _InfoRow(
              icon: Icons.air,
              label: '바람정보',
              value: '불러오는 중…',
            ),
            error: (_, _) =>
                const _InfoRow(icon: Icons.air, label: '바람정보', value: '정보 없음'),
            data: (m) {
              // 예보는 ±14일 전체가 오므로, 반드시 **선택한 날짜**의 값을
              // 골라야 한다(예전엔 hourly.first = 2주 전 값이라 날짜/지역을
              // 바꿔도 안 변하는 것처럼 보였다). 그날 09시에 가장 가까운
              // 시각을 대표로 쓴다.
              final target = DateTime(date.year, date.month, date.day, 9);
              HourlyMarine? h;
              var best = const Duration(days: 999);
              for (final e in m.hourly) {
                final diff = e.time.difference(target).abs();
                if (diff < best) {
                  best = diff;
                  h = e;
                }
              }
              final sameDay = h != null && DateUtils.isSameDay(h.time, date);
              return _InfoRow(
                icon: Icons.air,
                label: '바람정보',
                value: h == null || !sameDay
                    ? '이 날짜의 예보 없음'
                    : '${compassKo(h.windDirectionDeg)} '
                          '${h.windSpeedMs.toStringAsFixed(1)}m/s · '
                          '돌풍 ${h.windGustMs.toStringAsFixed(0)}m/s',
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '낚시지수 (${species.join(' · ')})',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // 어종 변경 버튼 — **이 지역에 값이 있는 어종만** 골라 바꾼다.
              InkWell(
                onTap: () => _editSpecies(
                  context,
                  ref,
                  custom,
                  fishingAsync.valueOrNull?.availableSpecies,
                ),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 13, color: Colors.white70),
                      SizedBox(width: 3),
                      Text(
                        '어종변경',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          fishingAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const Text(
              '낚시지수를 불러오지 못했습니다',
              style: TextStyle(color: Colors.white70),
            ),
            data: (f) {
              final groups = f.speciesGroupsForDate(
                date,
                preferredSpecies: species,
              );
              if (groups.isEmpty && estimated.isEmpty) {
                return const Text(
                  '이 날짜의 낚시지수가 없습니다',
                  style: TextStyle(color: Colors.white70),
                );
              }
              return Column(
                children: [
                  for (final g in groups)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _SpeciesIndexRow(indices: g),
                    ),
                  for (final e in estimated)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _EstimatedIndexRow(estimates: e),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 선택한 추정 어종의 오전·오후 등급을 만든다.
  ///
  /// 이미 화면에 있는 값만 쓴다 — 그날 물때·조위(조류 세기)와 지점 예보의
  /// 바람·파고. 추가 네트워크 호출이 없다. **그날 예보가 없으면 바람·파고를
  /// null로 넘겨 감점에서 아예 뺀다**(물때·제철로만 판단).
  List<List<JiggingEstimate>> _estimatesFor(
    List<String> species,
    MarineForecast? marine,
  ) {
    if (species.isEmpty) return const [];
    // 절대 조차가 아니라 **그 지점 기준 상대 세기**를 쓴다 — 서해는 조금에도
    // 조차가 커서 절대값으로는 늘 "급류"로 읽혔다.
    final strength = relativeTideStrength(
      mulTtae: mulTtaeFor(
        date,
        system: mulTtaeSystemForRegion(location.region),
      ),
      dayRangeCm: dailyTideRangeCm(tide.hourlyHeightsCm),
    );

    /// 그날 [hour]시에 가장 가까운 예보.
    HourlyMarine? at(int hour) {
      if (marine == null) return null;
      final target = DateTime(date.year, date.month, date.day, hour);
      HourlyMarine? best;
      var bestDiff = const Duration(days: 999);
      for (final h in marine.hourly) {
        final diff = h.time.difference(target).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          best = h;
        }
      }
      // 그날 값이 아니면(예보 범위 밖) 쓰지 않는다.
      return best != null && DateUtils.isSameDay(best.time, date) ? best : null;
    }

    final morning = at(9);
    final afternoon = at(15);

    JiggingEstimate one(String s, String slot, HourlyMarine? h) =>
        JiggingEstimate(
          species: s,
          timeSlot: slot,
          grade: estimateJiggingGrade(
            species: s,
            tideStrength: strength,
            windMs: h?.windSpeedMs,
            gustMs: h?.windGustMs,
            waveM: h?.waveHeightM,
            month: date.month,
          ),
        );

    return [
      for (final s in species) [one(s, '오전', morning), one(s, '오후', afternoon)],
    ];
  }

  /// 어종 선택 다이얼로그. 칩으로 최대 5종을 고르고, "제철 어종(자동)"을
  /// 누르면 선택을 비워 달별 제철 어종으로 되돌린다. 취소는 변경 없음.
  ///
  /// [available]은 이 지역 예보에 **실제로 값이 있는** 어종이다. 지수가 없는
  /// 어종을 고르면 화면이 빈칸으로 남으므로 아예 목록에서 뺀다. 예보를 아직
  /// 못 받았으면(null) 후보 전체를 보여준다.
  Future<void> _editSpecies(
    BuildContext context,
    WidgetRef ref,
    List<String> current,
    Set<String>? available,
  ) async {
    final options = [
      for (final s in fishingSpeciesCatalog)
        if (available == null || available.contains(s)) s,
      // 추정 어종은 관측 데이터와 무관하게(물때·바람으로) 계산하므로 항상 뜬다.
      ...estimatedSpeciesCatalog,
    ];
    // 자동 모드였다면 현재 화면의 제철 어종을 초기 선택으로 보여준다.
    // 값이 없는 어종은 초기 선택에서도 뺀다.
    final picked = [
      for (final s
          in (current.isNotEmpty ? current : seasonalSpecies(date.month)))
        if (options.contains(s)) s,
    ];
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('어종 선택 (최대 5종)'),
          content: options.isEmpty
              ? const Text('이 지역에는 어종별 지수가 없습니다.')
              : SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: -4,
                    children: [
                      for (final s in options)
                        FilterChip(
                          label: Text(s),
                          selected: picked.contains(s),
                          onSelected: (v) => setState(() {
                            if (v) {
                              if (picked.length <
                                  TideFishingSpeciesNotifier.maxCount) {
                                picked.add(s);
                              }
                            } else {
                              picked.remove(s);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, const <String>[]),
              child: const Text('제철 어종(자동)'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: picked.isEmpty
                  ? null
                  : () => Navigator.pop(context, picked),
              child: const Text('적용'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      ref.read(tideFishingSpeciesProvider.notifier).set(result);
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.white70),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// 한 어종의 시간대별 지수를 등급 칩으로 요약.
class _SpeciesIndexRow extends StatelessWidget {
  const _SpeciesIndexRow({required this.indices});

  final List<FishingIndex> indices;

  Color _gradeColor(FishingGrade g) => switch (g) {
    FishingGrade.veryGood => const Color(0xFF2E9E5B),
    FishingGrade.good => const Color(0xFF6BB94D),
    FishingGrade.normal => const Color(0xFFC9A227),
    FishingGrade.bad => const Color(0xFFCC7A29),
    FishingGrade.veryBad => const Color(0xFFC24444),
  };

  @override
  Widget build(BuildContext context) {
    final name = indices.first.species ?? '대표';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          for (final i in indices.take(3)) ...[
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _gradeColor(i.grade),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${i.timeSlot} ${i.grade.label}',
                style: const TextStyle(color: Colors.white, fontSize: 10.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 추정 어종 한 줄. 관측 기반 행([_SpeciesIndexRow])과 같은 모양이되
/// **"추정" 배지**를 달아 관측값과 구분한다 — 이 값은 물때·바람으로 계산한
/// 것이라 관측 지수와 같은 근거가 아니다.
class _EstimatedIndexRow extends StatelessWidget {
  const _EstimatedIndexRow({required this.estimates});

  final List<JiggingEstimate> estimates;

  Color _gradeColor(FishingGrade g) => switch (g) {
    FishingGrade.veryGood => const Color(0xFF2E9E5B),
    FishingGrade.good => const Color(0xFF6BB94D),
    FishingGrade.normal => const Color(0xFFC9A227),
    FishingGrade.bad => const Color(0xFFCC7A29),
    FishingGrade.veryBad => const Color(0xFFC24444),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(
            estimates.first.species,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white38),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              '추정',
              style: TextStyle(color: Colors.white70, fontSize: 9.5),
            ),
          ),
          const Spacer(),
          for (final e in estimates) ...[
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _gradeColor(e.grade),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${e.timeSlot} ${e.grade.label}',
                style: const TextStyle(color: Colors.white, fontSize: 10.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 날씨 패널: 물때에서 선택한 항구(동일 지역)의 날씨만 컴팩트하게.
class _WeatherPanel extends ConsumerWidget {
  const _WeatherPanel({required this.location, required this.date});

  final SeaLocation location;

  /// 물때 화면에서 선택한 날짜 — 시간별 예보의 시작 기준이 된다.
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecastAsync = ref.watch(weatherForecastProvider(location));
    return _PanelBox(
      title: '날씨 · ${location.name} (향후 2주)',
      child: forecastAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text(
            '날씨를 불러오지 못했습니다',
            style: TextStyle(color: Colors.white70),
          ),
        ),
        data: (f) {
          final now = DateTime.now();
          // 시간별은 **선택한 날짜의 0시부터**(오늘이면 현재부터) 48시간
          // (3시간 간격)까지 우측으로 스크롤해 볼 수 있다.
          final start = DateUtils.isSameDay(date, now) || date.isBefore(now)
              ? now.subtract(const Duration(hours: 1))
              : DateTime(date.year, date.month, date.day);
          final hours = f.hourly
              .where(
                (h) =>
                    !h.time.isBefore(start) &&
                    h.time.isBefore(start.add(const Duration(hours: 48))) &&
                    h.time.hour % 3 == 0,
              )
              .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  WeatherIcon(code: f.now.weatherCode, size: 34),
                  const SizedBox(width: 8),
                  Text(
                    '${f.now.tempC.round()}°  ${wmoLabelKo(f.now.weatherCode)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: hours.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, i) {
                    final h = hours[i];
                    // 어느 날짜의 시각인지 알 수 있게 첫 칩과 자정 칩에
                    // 날짜(M/d)를 표시한다(사용자 요구).
                    final showDate = i == 0 || h.time.hour == 0;
                    return Container(
                      width: 46,
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            showDate ? '${h.time.month}/${h.time.day}' : ' ',
                            style: const TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${h.time.hour}시',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                          WeatherIcon(code: h.weatherCode, size: 20),
                          Text(
                            '${h.tempC.round()}°',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final d in f.daily.take(15))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 44,
                              child: Text(
                                '${d.date.month}/${d.date.day}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            WeatherIcon(code: d.weatherCode, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '${d.tempMinC.round()}°/${d.tempMaxC.round()}°',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '강수 ${d.precipProbMaxPct}%',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 물때달력 패널: 그래프 자리에 그대로 그린다. 날짜 탭 → 그 날짜 선택 후
/// 타임라인으로 복귀.
class _CalendarPanel extends StatelessWidget {
  const _CalendarPanel({
    required this.initial,
    required this.minDate,
    required this.maxDate,
    required this.system,
    required this.onPicked,
  });

  final DateTime initial;
  final DateTime minDate;
  final DateTime maxDate;
  final MulTtaeSystem system;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 56),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // 달력은 테마 색을 쓰므로 반투명 표면 위에 올린다(투명도 70%).
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SingleChildScrollView(
        child: MulTtaeCalendarView(
          initial: initial,
          minDate: minDate,
          maxDate: maxDate,
          system: system,
          onPicked: onPicked,
        ),
      ),
    );
  }
}

/// 조위그래프 패널: 반투명 배경(투명도 추가) 위에 상세 조위 곡선.
class _ChartPanel extends StatelessWidget {
  const _ChartPanel({required this.tide, required this.isToday});

  final TideDay tide;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 차트는 테마 색으로 그려지므로, 달력처럼 테마 표면 위에 올려야 잘
    // 보인다(다크 테마=어두운 표면+밝은 선, 라이트=밝은 표면+어두운 선 —
    // 사용자 요구: 배경 밝기에 맞춰 반전).
    return Container(
      margin: const EdgeInsets.only(right: 56),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('상세 조위 그래프', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: TideChart(
                  hourlyHeightsCm: tide.hourlyHeightsCm,
                  now: isToday ? DateTime.now() : null,
                ),
              ),
            ),
          ),
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
