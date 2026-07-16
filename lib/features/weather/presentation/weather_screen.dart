import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../locations/data/models/sea_location.dart';
import '../../locations/data/sample_locations.dart';
import '../../locations/presentation/providers.dart';
import '../data/models/marine_weather.dart';
import '../data/models/wind_field.dart';
import 'providers.dart';
import 'wind_field_providers.dart';
import 'widgets/wind_arrow.dart';
import 'widgets/wind_heatmap.dart';
import 'widgets/wind_map_painter.dart';

/// 바람·해양 날씨 화면 (윈디 영역).
///
/// 첫 화면이 바로 바람 지도다: 지역을 탭하면 그 지역이 선택되고,
/// 지도 아래 시간 스크러버로 시간대를 옮기면 바람 흐름과 하단 상세 정보가
/// 함께 그 시각 기준으로 바뀐다.
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
  static const _maxTrail = 8;
  static const _maxAgeSeconds = 10.0;

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
      p.lat += v * _degreesPerMps * dt;
      p.lon += u * _degreesPerMps * dt;
      p.age += dt;

      final nx = (p.lon - field.minLon) / (field.maxLon - field.minLon);
      final ny = 1 - (p.lat - field.minLat) / (field.maxLat - field.minLat);
      p.trail.add(Offset(nx, ny));
      if (p.trail.length > _maxTrail) p.trail.removeAt(0);

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
      appBar: AppBar(title: const Text('해양 날씨')),
      body: seriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('바람장을 불러오지 못했습니다: $e')),
        data: (series) {
          _ensureSeeded(series);
          final field = series.at(_hourOffset);
          return Column(
            children: [
              SizedBox(
                height: 240,
                child: _WindMapArea(
                  field: field,
                  particles: _particles,
                  selected: selected,
                  onLocationTap: (loc) =>
                      ref.read(selectedLocationProvider.notifier).select(loc),
                ),
              ),
              const WindSpeedLegend(),
              _TimeScrubber(
                times: series.hourly.map((f) => f.time).toList(),
                value: _hourOffset,
                onChanged: (v) => setState(() => _hourOffset = v),
              ),
              Expanded(
                child: _DetailPanel(
                  location: selected,
                  hourOffset: _hourOffset,
                  onHourTap: (v) => setState(() => _hourOffset = v),
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
/// 마커를 탭하면 해당 지역이 선택되고, 손가락으로 확대/축소·이동할 수 있다.
class _WindMapArea extends StatefulWidget {
  const _WindMapArea({
    required this.field,
    required this.particles,
    required this.selected,
    required this.onLocationTap,
  });

  final WindField field;
  final List<WindParticle> particles;
  final SeaLocation selected;
  final ValueChanged<SeaLocation> onLocationTap;

  @override
  State<_WindMapArea> createState() => _WindMapAreaState();
}

class _WindMapAreaState extends State<_WindMapArea> {
  ui.Image? _heatmap;
  DateTime? _heatmapTime;

  @override
  void initState() {
    super.initState();
    _rebuildHeatmap();
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
    _heatmap?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B2A4A), Color(0xFF08182B)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final heatmap = _heatmap;
          return InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                children: [
                  if (heatmap != null)
                    CustomPaint(
                      painter: WindHeatmapPainter(image: heatmap),
                      size: size,
                    ),
                  CustomPaint(
                    painter: WindMapPainter(
                      particles: widget.particles,
                      color: Colors.white,
                    ),
                    size: size,
                  ),
                  for (final loc in sampleLocations)
                    if (field.contains(loc.latitude, loc.longitude))
                      _LocationMarker(
                        location: loc,
                        highlighted: loc.id == widget.selected.id,
                        onTap: () => widget.onLocationTap(loc),
                        left:
                            (loc.longitude - field.minLon) /
                                (field.maxLon - field.minLon) *
                                size.width -
                            10,
                        top:
                            (1 -
                                    (loc.latitude - field.minLat) /
                                        (field.maxLat - field.minLat)) *
                                size.height -
                            10,
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LocationMarker extends StatelessWidget {
  const _LocationMarker({
    required this.location,
    required this.highlighted,
    required this.onTap,
    required this.left,
    required this.top,
  });

  final SeaLocation location;
  final bool highlighted;
  final VoidCallback onTap;
  final double left;
  final double top;

  @override
  Widget build(BuildContext context) {
    final dotSize = highlighted ? 12.0 : 8.0;
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(6),
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
              if (highlighted) ...[
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
    final isNow = value == 0;
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
            width: 96,
            child: Text(
              isNow
                  ? '지금 (${formatHm(t)})'
                  : '${formatMonthDay(t)} ${formatHm(t)}',
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

/// 지도 아래 상세 정보: 스크러버 시각 기준 요약 + 시간별 예보 목록.
class _DetailPanel extends ConsumerWidget {
  const _DetailPanel({
    required this.location,
    required this.hourOffset,
    required this.onHourTap,
  });

  final SeaLocation location;
  final int hourOffset;
  final ValueChanged<int> onHourTap;

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
          padding: const EdgeInsets.all(16),
          children: [
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
            onTap: () => onHourTap(i),
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
