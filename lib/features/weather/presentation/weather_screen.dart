import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../locations/data/models/sea_location.dart';
import '../../locations/data/sample_locations.dart';
import '../../locations/presentation/providers.dart';
import '../../locations/presentation/widgets/region_selector_action.dart';
import '../data/models/marine_weather.dart';
import '../data/models/wind_field.dart';
import 'providers.dart';
import 'wind_field_providers.dart';
import 'widgets/coastline_painter.dart';
import 'widgets/map_city_labels.dart';
import 'widgets/map_projection.dart';
import 'widgets/wind_arrow.dart';
import 'widgets/wind_heatmap.dart';
import 'widgets/wind_map_painter.dart';

/// 바람·해양 날씨 화면 (윈디 영역).
///
/// 지도가 화면 전체를 채우고 항상 확대/축소·이동할 수 있다(핀치 줌).
/// 지도를 탭하면 그 지점에 핀이 꽂히고 "이 지점의 예보" 말풍선이 떠서,
/// 임의 좌표의 시간별 예보 표(forecast at this point)를 볼 수 있다.
/// 하단 바에는 현재 선택 지역의 요약이 뜨고, 탭하면 시간별 상세 목록이
/// 바텀시트로 펼쳐진다(윈디 앱의 지도 → 정보 패널 구조를 참고했다).
class WeatherScreen extends ConsumerStatefulWidget {
  const WeatherScreen({super.key});

  @override
  ConsumerState<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends ConsumerState<WeatherScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  final _random = math.Random();
  final List<WindParticle> _particles = [];
  WindFieldSeries? _series;
  int _hourOffset = 0;

  static const _particleCount = 220;
  static const _maxAgeSeconds = 10.0;

  /// 궤적 길이(포인트 수)를 풍속에 비례해 늘려, 바람이 셀수록 흰 점이
  /// 짧은 선 → 조금 긴 선 → 아주 긴 선으로 보이게 한다.
  static const _minTrail = 3;
  static const _maxTrailCap = 24;
  static const _trailSpeedFactor = 1.6;

  /// 위경도 이동 배율(도/초 per m/s) — 화면 안에서 흐름이 보이도록 과장한
  /// 시각적 배율이며, 실제 지리적 이동 속도가 아니다.
  static const _degreesPerMps = 0.02;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _ensureSeeded(WindFieldSeries series) {
    if (_series != null) return;
    _series = series;
    final field = series.at(_hourOffset);
    _particles
      ..clear()
      ..addAll(List.generate(_particleCount, (_) => _spawnParticle(field)));
    _ticker.start();
  }

  WindParticle _spawnParticle(WindField field) => WindParticle(
    lat: field.minLat + _random.nextDouble() * (field.maxLat - field.minLat),
    lon: field.minLon + _random.nextDouble() * (field.maxLon - field.minLon),
    age: _random.nextDouble() * _maxAgeSeconds,
    trail: [],
  );

  void _onTick(Duration elapsed) {
    final series = _series;
    if (series == null) return;
    final field = series.at(_hourOffset);
    final dt = _lastElapsed == Duration.zero
        ? 1 / 60
        : (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.25) return; // 첫 프레임/백그라운드 복귀 시 큰 점프 무시

    for (var i = 0; i < _particles.length; i++) {
      final p = _particles[i];
      final uv = field.sample(p.lat, p.lon);
      if (uv == null) {
        _particles[i] = _spawnParticle(field);
        continue;
      }
      final (u, v) = uv;
      final speed = math.sqrt(u * u + v * v);
      p.lat += v * _degreesPerMps * dt;
      p.lon += u * _degreesPerMps * dt;
      p.age += dt;

      final nx = (p.lon - field.minLon) / (field.maxLon - field.minLon);
      final ny = 1 - (p.lat - field.minLat) / (field.maxLat - field.minLat);
      p.trail.add(Offset(nx, ny));
      final maxTrail = (_minTrail + speed * _trailSpeedFactor)
          .clamp(_minTrail, _maxTrailCap)
          .round();
      while (p.trail.length > maxTrail) {
        p.trail.removeAt(0);
      }

      if (p.age > _maxAgeSeconds || !field.contains(p.lat, p.lon)) {
        _particles[i] = _spawnParticle(field);
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final seriesAsync = ref.watch(windFieldSeriesProvider);
    final selected = ref.watch(selectedLocationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Windy(윈디)'),
        actions: const [RegionSelectorAction()],
      ),
      body: seriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('바람장을 불러오지 못했습니다: $e')),
        data: (series) {
          _ensureSeeded(series);
          final field = series.at(_hourOffset);
          final times = series.hourly.map((f) => f.time).toList();
          return Stack(
            children: [
              Positioned.fill(
                child: _WindMapArea(
                  field: field,
                  particles: _particles,
                  selected: selected,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _BottomInfoBar(
                  selected: selected,
                  times: times,
                  hourOffset: _hourOffset,
                  onHourChanged: (v) => setState(() => _hourOffset = v),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 지도 영역: 풍속 색상 히트맵 + 파티클 흐름 + 지역 마커.
/// 아무 곳이나 탭하면 그 지점에 핀이 꽂히고 "이 지점의 예보" 말풍선이
/// 뜬다(윈디의 forecast at this point). 손가락으로 확대/축소·이동할 수
/// 있고, 확대할수록 지점 이름이 더 많이 보인다.
class _WindMapArea extends StatefulWidget {
  const _WindMapArea({
    required this.field,
    required this.particles,
    required this.selected,
  });

  final WindField field;
  final List<WindParticle> particles;
  final SeaLocation selected;

  @override
  State<_WindMapArea> createState() => _WindMapAreaState();
}

class _WindMapAreaState extends State<_WindMapArea> {
  ui.Image? _heatmap;
  DateTime? _heatmapTime;
  final TransformationController _transformController =
      TransformationController();
  double _scale = 1.0;

  /// 사용자가 지도에서 콕 찍은 지점(임의 좌표). null이면 아직 안 찍음.
  double? _pickedLat;
  double? _pickedLon;

  @override
  void initState() {
    super.initState();
    _rebuildHeatmap();
    _transformController.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    final newScale = _transformController.value.getMaxScaleOnAxis();
    if ((newScale - _scale).abs() > 0.02) {
      setState(() => _scale = newScale);
    }
  }

  @override
  void didUpdateWidget(covariant _WindMapArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.field.time != _heatmapTime) {
      _rebuildHeatmap();
    }
  }

  Future<void> _rebuildHeatmap() async {
    final field = widget.field;
    final time = field.time;
    final image = await buildWindHeatmapImage(field);
    if (!mounted || widget.field.time != time) {
      image.dispose();
      return;
    }
    _heatmap?.dispose();
    setState(() {
      _heatmap = image;
      _heatmapTime = time;
    });
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    _heatmap?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B2A4A), Color(0xFF08182B)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final heatmap = _heatmap;
          // 지도 뷰(mapViewBounds)는 바람장 격자와 같은 범위를 쓴다 —
          // 히트맵이 지도 전체를 채운다. 모든 레이어가 같은 투영을 공유해
          // 서로 어긋나지 않게 한다.
          final projection = MapProjection(mapViewBounds, size);
          final fieldRect = projection.rectFor(
            LatLonBounds(
              minLat: field.minLat,
              maxLat: field.maxLat,
              minLon: field.minLon,
              maxLon: field.maxLon,
            ),
          );
          // 어느 정도 확대했을 때만 나머지 지점 이름을 보여준다(기본 화면
          // 에서는 선택된 지점 이름만 표시해 지도를 깔끔하게 유지한다).
          final showAllLabels = _scale > 1.8;
          return InteractiveViewer(
            transformationController: _transformController,
            minScale: 1,
            maxScale: 6,
            // 기본값(EdgeInsets.zero)을 그대로 써서 지도 바깥(빈 배경)이
            // 보이는 지점까지는 이동할 수 없게 한다 — 끝까지 이동하면
            // 지도 가장자리에서 멈춘다.
            boundaryMargin: EdgeInsets.zero,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final lat = projection.latFor(details.localPosition.dy);
                final lon = projection.lonFor(details.localPosition.dx);
                if (!field.contains(lat, lon)) return;
                setState(() {
                  _pickedLat = lat;
                  _pickedLon = lon;
                });
              },
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: Stack(
                  children: [
                    if (heatmap != null)
                      CustomPaint(
                        painter: WindHeatmapPainter(
                          image: heatmap,
                          dstRect: fieldRect,
                        ),
                        size: size,
                      ),
                    CustomPaint(
                      painter: CoastlinePainter(projection: projection),
                      size: size,
                    ),
                    Positioned.fromRect(
                      rect: fieldRect,
                      child: CustomPaint(
                        painter: WindMapPainter(
                          particles: widget.particles,
                          color: Colors.white,
                        ),
                        size: fieldRect.size,
                      ),
                    ),
                    MapCityLabelLayer(projection: projection, scale: _scale),
                    for (final loc in sampleLocations)
                      if (field.contains(loc.latitude, loc.longitude))
                        _LocationMarker(
                          location: loc,
                          highlighted: loc.id == widget.selected.id,
                          showLabel:
                              loc.id == widget.selected.id || showAllLabels,
                          scale: _scale,
                          left: projection.x(loc.longitude) - 10,
                          top: projection.y(loc.latitude) - 10,
                        ),
                    if (_pickedLat case final plat?)
                      if (_pickedLon case final plon?)
                        _PointCallout(
                          scale: _scale,
                          left: projection.x(plon),
                          top: projection.y(plat),
                          lat: plat,
                          lon: plon,
                          onTap: () =>
                              _openPointForecastSheet(context, plat, plon),
                        ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 지도 위 지점 표시. 탭 처리는 지도 전체 [GestureDetector]가 맡으므로
/// 여기서는 순수하게 점 + (조건부) 이름만 그린다.
class _LocationMarker extends StatelessWidget {
  const _LocationMarker({
    required this.location,
    required this.highlighted,
    required this.showLabel,
    required this.scale,
    required this.left,
    required this.top,
  });

  final SeaLocation location;
  final bool highlighted;
  final bool showLabel;

  /// 지도의 현재 확대 배율 — 마커(점+이름)가 지도와 함께 커지지 않고
  /// 항상 같은 화면 크기로 보이도록 반대로 축소하는 데 쓴다.
  final double scale;
  final double left;
  final double top;

  @override
  Widget build(BuildContext context) {
    final dotSize = highlighted ? 12.0 : 6.0;
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Transform.scale(
          scale: 1 / scale,
          alignment: Alignment.topLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: highlighted ? Colors.amberAccent : Colors.white70,
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 2),
                  ],
                ),
              ),
              if (showLabel) ...[
                const SizedBox(width: 4),
                Text(
                  location.name,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 지도 위에 겹쳐 뜨는 하단 바: 풍속 범례 + 시간 스크러버 + 선택 지점
/// 요약. 요약을 탭하면 시간별 상세 목록이 바텀시트로 펼쳐진다.
class _BottomInfoBar extends ConsumerWidget {
  const _BottomInfoBar({
    required this.selected,
    required this.times,
    required this.hourOffset,
    required this.onHourChanged,
  });

  final SeaLocation selected;
  final List<DateTime> times;
  final int hourOffset;
  final ValueChanged<int> onHourChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecastAsync = ref.watch(marineForecastProvider(selected));
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 16)],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const WindSpeedLegend(),
            _TimeScrubber(
              times: times,
              value: hourOffset,
              onChanged: onHourChanged,
            ),
            InkWell(
              onTap: () => _openDetailSheet(
                context,
                location: selected,
                hourOffset: hourOffset,
                onHourTap: onHourChanged,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
                child: forecastAsync.when(
                  loading: () => const SizedBox(
                    height: 40,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (e, _) => Text(
                    '예보를 불러오지 못했습니다',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  data: (forecast) {
                    final index = hourOffset.clamp(
                      0,
                      forecast.hourly.length - 1,
                    );
                    final at = forecast.hourly[index];
                    return Row(
                      children: [
                        WindArrow(directionDeg: at.windDirectionDeg, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selected.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${compassKo(at.windDirectionDeg)}풍 '
                                '${formatWind(at.windSpeedMs)} · 파고 '
                                '${formatWave(at.waveHeightM)} '
                                '(${formatPeriod(at.wavePeriodS)})',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_up),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _openDetailSheet(
  BuildContext context, {
  required SeaLocation location,
  required int hourOffset,
  required ValueChanged<int> onHourTap,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, scrollController) => _DetailSheetContent(
        location: location,
        hourOffset: hourOffset,
        onHourTap: onHourTap,
        scrollController: scrollController,
      ),
    ),
  );
}

/// 지도 아래 상세 정보 바텀시트: 스크러버 시각 기준 요약 + 시간별 예보
/// 목록(윈디처럼 지점을 탭하면 뜨는 상세 패널). 목록에서 시각을 고르면
/// 지도의 시간 스크러버에 반영되고 시트가 닫힌다.
class _DetailSheetContent extends ConsumerWidget {
  const _DetailSheetContent({
    required this.location,
    required this.hourOffset,
    required this.onHourTap,
    required this.scrollController,
  });

  final SeaLocation location;
  final int hourOffset;
  final ValueChanged<int> onHourTap;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecastAsync = ref.watch(marineForecastProvider(location));
    return forecastAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('예보를 불러오지 못했습니다: $e')),
      data: (forecast) {
        final index = hourOffset.clamp(0, forecast.hourly.length - 1);
        final at = forecast.hourly[index];
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(location.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _SummaryItem(
                      icon: WindArrow(
                        directionDeg: at.windDirectionDeg,
                        size: 28,
                      ),
                      value: formatWind(at.windSpeedMs),
                      label:
                          '${compassKo(at.windDirectionDeg)}풍 · '
                          '돌풍 ${formatWind(at.windGustMs)}',
                    ),
                    _SummaryItem(
                      icon: const Icon(Icons.waves, size: 28),
                      value:
                          '${formatWave(at.waveHeightM)} ${formatPeriod(at.wavePeriodS)}',
                      label: '파고 · 주기 (${compassKo(at.waveDirectionDeg)}향)',
                    ),
                    _SummaryItem(
                      icon: const Icon(Icons.thermostat, size: 28),
                      value: '${at.waterTempC.toStringAsFixed(1)}°',
                      label: '수온',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('시간별 예보', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            ..._hourlyItems(forecast, index, context),
          ],
        );
      },
    );
  }

  List<Widget> _hourlyItems(
    MarineForecast forecast,
    int selectedIndex,
    BuildContext context,
  ) {
    DateTime? currentDay;
    final widgets = <Widget>[];
    for (var i = 0; i < forecast.hourly.length; i++) {
      final h = forecast.hourly[i];
      final day = DateUtils.dateOnly(h.time);
      if (currentDay == null || day != currentDay) {
        currentDay = day;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              formatMonthDay(day),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        );
      }
      final hoursFromStart = h.time.difference(forecast.hourly.first.time);
      final show =
          hoursFromStart <= const Duration(hours: 48) || h.time.hour % 3 == 0;
      if (!show) continue;

      final isSelected = i == selectedIndex;
      widgets.add(
        Material(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              onHourTap(i);
              Navigator.of(context).pop();
            },
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
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
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}

/// 시간 스크러버: 좌우로 밀면 지도·상세 정보가 그 시각 기준으로 바뀐다.
class _TimeScrubber extends StatelessWidget {
  const _TimeScrubber({
    required this.times,
    required this.value,
    required this.onChanged,
  });

  final List<DateTime> times;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (times.isEmpty) return const SizedBox.shrink();
    final t = times[value.clamp(0, times.length - 1)];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(
            Icons.schedule,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 128,
            child: Text(
              '${formatMonthDay(t)} ${formatHm(t)}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          Expanded(
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: (times.length - 1).toDouble(),
              divisions: times.length > 1 ? times.length - 1 : null,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ],
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

/// 임의 좌표를 위한 즉석 [SeaLocation]. id를 반올림 좌표로 만들어
/// 같은 지점을 다시 찍으면 예보 캐시가 재사용되게 한다.
SeaLocation pointSeaLocation(double lat, double lon) {
  final latR = lat.toStringAsFixed(3);
  final lonR = lon.toStringAsFixed(3);
  return SeaLocation(
    id: 'pt_${latR}_$lonR',
    name: '위도 $latR · 경도 $lonR',
    region: '해상',
    latitude: lat,
    longitude: lon,
  );
}

/// 지도에서 찍은 지점 위에 뜨는 "이 지점의 예보" 말풍선 + 핀.
/// 지도 마커처럼 확대해도 크기가 일정하도록 반대로 축소한다.
class _PointCallout extends StatelessWidget {
  const _PointCallout({
    required this.scale,
    required this.left,
    required this.top,
    required this.lat,
    required this.lon,
    required this.onTap,
  });

  final double scale;
  final double left;
  final double top;
  final double lat;
  final double lon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: left,
      top: top,
      // 말풍선의 바닥 중앙(핀 끝)이 찍은 좌표에 오도록 옮긴 뒤,
      // 그 지점을 기준으로 반대로 축소해 화면상 크기를 일정하게 유지한다.
      child: FractionalTranslation(
        translation: const Offset(-0.5, -1),
        child: Transform.scale(
          scale: 1 / scale,
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(16),
                elevation: 3,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.insights, size: 14, color: scheme.onPrimary),
                        const SizedBox(width: 4),
                        Text(
                          '이 지점의 예보',
                          style: TextStyle(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Icon(
                Icons.location_on,
                color: scheme.primary,
                size: 30,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _openPointForecastSheet(BuildContext context, double lat, double lon) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => _PointForecastSheet(
        location: pointSeaLocation(lat, lon),
        scrollController: scrollController,
      ),
    ),
  );
}

/// forecast at this point: 찍은 지점의 시간별 예보를 윈디식 표로 보여준다.
/// 행 = 항목(기온·바람·돌풍·파도·너울·너울주기·파력), 열 = 시각.
class _PointForecastSheet extends ConsumerWidget {
  const _PointForecastSheet({
    required this.location,
    required this.scrollController,
  });

  final SeaLocation location;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecastAsync = ref.watch(marineForecastProvider(location));
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '선택한 지점의 예보',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${location.name}  ·  Open-Meteo 해양 예보',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: forecastAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('예보를 불러오지 못했습니다: $e')),
            data: (forecast) {
              // 향후 60시간(현재 시각부터)을 시간별로 보여준다.
              final hours = forecast.hourly.take(60).toList();
              return SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                child: _ForecastTable(hours: hours),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 윈디식 시간별 예보 표. 왼쪽 항목 열은 고정, 오른쪽 시각 열은 가로 스크롤.
class _ForecastTable extends StatelessWidget {
  const _ForecastTable({required this.hours});

  final List<HourlyMarine> hours;

  static const double _timeH = 42;
  static const double _rowH = 30;
  static const double _colW = 54;
  static const double _labelW = 68;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodySmall;
    Widget label(String text, double h) => SizedBox(
      height: h,
      width: _labelW,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(text, style: labelStyle),
        ),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            label('시간', _timeH),
            label('기온', _rowH),
            label('바람 m/s', _rowH),
            label('돌풍 m/s', _rowH),
            label('파도 m', _rowH),
            label('너울 m', _rowH),
            label('너울주기 s', _rowH),
            label('파력 kW/m', _rowH),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < hours.length; i++)
                  _HourColumn(
                    hour: hours[i],
                    isNewDay:
                        i == 0 ||
                        !DateUtils.isSameDay(hours[i].time, hours[i - 1].time),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HourColumn extends StatelessWidget {
  const _HourColumn({required this.hour, required this.isNewDay});

  final HourlyMarine hour;
  final bool isNewDay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final windColor = windSpeedColor(hour.windSpeedMs);
    // 밝은 풍속색 위에서는 검은 글씨가 잘 보이도록 명도로 대비색을 고른다.
    final windText = windColor.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;

    Widget cell(
      String text, {
      Color? bg,
      Color? fg,
      double h = _ForecastTable._rowH,
    }) => Container(
      width: _ForecastTable._colW,
      height: h,
      alignment: Alignment.center,
      color: bg,
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg),
      ),
    );

    return Column(
      children: [
        // 시각(+날짜가 바뀌면 위에 날짜).
        Container(
          width: _ForecastTable._colW,
          height: _ForecastTable._timeH,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              left: isNewDay
                  ? BorderSide(color: scheme.outlineVariant)
                  : BorderSide.none,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isNewDay ? '${hour.time.day}일(${weekdayKo(hour.time)})' : '',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${hour.time.hour}시',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        cell('${hour.airTempC.round()}°'),
        cell(hour.windSpeedMs.round().toString(), bg: windColor, fg: windText),
        cell('${hour.windGustMs.round()}', fg: scheme.onSurfaceVariant),
        cell(hour.waveHeightM.toStringAsFixed(1)),
        cell(hour.swellHeightM.toStringAsFixed(1)),
        cell('${hour.swellPeriodS.round()}'),
        cell(formatWavePower(hour.wavePowerKw)),
      ],
    );
  }
}
