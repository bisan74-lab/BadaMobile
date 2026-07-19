import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../locations/data/models/sea_location.dart';
import '../../locations/presentation/providers.dart';
import '../../locations/presentation/widgets/region_selector_action.dart';
import '../../kma_weather/presentation/widgets/weather_icon.dart';
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

  /// 파티클 애니메이션 전용 리페인트 신호. 매 프레임 이 값만 올려
  /// **바람 레이어만** 다시 그리고, 위젯 트리 전체를 rebuild하지 않는다
  /// (60fps setState는 지도·해안선·라벨까지 매 프레임 재구성해 프레임을
  /// 떨어뜨리고 ANR로 앱이 종료됐다).
  final ValueNotifier<int> _repaint = ValueNotifier(0);

  /// 예보 표에서 선택 중인 시각의 해양값 — 지도 위 방향 나침반과 공유한다.
  final ValueNotifier<HourlyMarine?> _roseHour = ValueNotifier(null);
  WindFieldSeries? _series;
  int _hourOffset = 0;

  /// forecast at this point로 선택한 지점. null이면 일반(선택 지역) 모드.
  SeaLocation? _forecastPoint;

  static const _particleCount = 170;
  static const _maxAgeSeconds = 18.0;

  /// 궤적 길이(포인트 수)를 풍속에 비례해 늘려, 바람이 셀수록 흰 점이
  /// 짧은 선 → 조금 긴 선 → 아주 긴 흐름선으로 보이게 한다(윈디식 잔상).
  /// 올챙이처럼 꼬리가 길게 남도록 상한을 넉넉히 잡되, 풍속 비례 계수를
  /// 키워 센 바람일수록 확실히 더 길어지게 한다. 성능(프레임당 drawLine 수
  /// = 파티클수 × 궤적)을 위해 파티클 수는 낮춘다.
  static const _minTrail = 22;
  static const _maxTrailCap = 112;
  static const _trailSpeedFactor = 7.0;

  /// 위경도 이동 배율(도/초 per m/s) — 화면 안 흐름선의 이동 "속도"를 정하는
  /// 시각적 배율이며 실제 지리 이동 속도가 아니다. Windy에 맞춰 0.18로 둔다.
  static const _degreesPerMps = 0.18;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    _roseHour.dispose();
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
    // 위젯 트리 전체를 rebuild하지 않고 바람 레이어만 다시 그린다.
    _repaint.value++;
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
                  repaint: _repaint,
                  forecastPoint: _forecastPoint,
                  roseHour: _roseHour,
                  onForecast: (lat, lon) => setState(
                    () => _forecastPoint = pointSeaLocation(lat, lon),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _forecastPoint != null
                    ? _PointForecastPanel(
                        location: _forecastPoint!,
                        roseHour: _roseHour,
                        onClose: () {
                          _roseHour.value = null;
                          setState(() => _forecastPoint = null);
                        },
                      )
                    : _BottomInfoBar(
                        selected: selected,
                        times: times,
                        hourOffset: _hourOffset,
                        onHourChanged: (v) => setState(() => _hourOffset = v),
                        onOpenForecast: () =>
                            setState(() => _forecastPoint = selected),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 지도 영역: 풍속 색상 히트맵 + 파티클 흐름선 + 해안선 + 도시 라벨.
/// 아무 곳이나 탭하면 그 지점에 핀이 꽂히고 "이 지점의 예보" 말풍선이
/// 뜬다(윈디의 forecast at this point). 손가락으로 확대/축소·이동할 수
/// 있고, 확대할수록 도시 이름이 더 많이 보인다.
class _WindMapArea extends StatefulWidget {
  const _WindMapArea({
    required this.field,
    required this.particles,
    required this.repaint,
    required this.forecastPoint,
    required this.roseHour,
    required this.onForecast,
  });

  final WindField field;
  final List<WindParticle> particles;

  /// 매 프레임 파티클 레이어만 다시 그리게 하는 리페인트 신호.
  final Listenable repaint;

  /// 현재 예보 모드로 켜진 지점(있으면 그 지점에 방향 나침반을 그린다).
  final SeaLocation? forecastPoint;

  /// 방향 나침반에 표시할 현재 선택 시각의 해양값(예보 표와 공유).
  final ValueNotifier<HourlyMarine?> roseHour;

  /// "이 지점의 예보" 버튼 → 해당 좌표로 예보 모드 진입.
  final void Function(double lat, double lon) onForecast;

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
          return InteractiveViewer(
            transformationController: _transformController,
            minScale: 1,
            // 섬 이름까지 보이도록 더 깊게 확대할 수 있게 한다.
            maxScale: 14,
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
                // 이미 "이 지점의 예보" 표가 열려 있으면, 새로 찍은 지점으로
                // 바로 예보를 갱신한다(말풍선 버튼을 다시 누를 필요 없이 실시간
                // 이동). 닫혀 있으면 말풍선만 띄우고, 버튼을 눌러야 열린다.
                if (widget.forecastPoint != null) {
                  widget.onForecast(lat, lon);
                }
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
                    // RepaintBoundary로 감싸지 않는다 — 감싸면 base 해상도로
                    // 래스터화된 뒤 확대되어 흐려지고, 1/scale 두께가 사라진다.
                    // 그냥 두면 InteractiveViewer의 변환 레이어가 벡터를 확대
                    // 배율로 다시 그려 선이 선명하고, strokeWidth=0.6/scale이
                    // 화면상 항상 얇게 유지된다. (파티클 레이어는 자체
                    // RepaintBoundary가 있어 이 해안선은 매 프레임 다시 그려지지
                    // 않는다.)
                    CustomPaint(
                      painter: CoastlinePainter(
                        projection: projection,
                        scale: _scale,
                      ),
                      size: size,
                    ),
                    Positioned.fromRect(
                      rect: fieldRect,
                      // 파티클만 매 프레임 다시 그려지도록 경계를 둔다.
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: WindMapPainter(
                            particles: widget.particles,
                            // 순백이 아니라 살짝 흐린 회백색으로 은은하게.
                            color: const Color(0xFFDCE6F0),
                            repaint: widget.repaint,
                          ),
                          size: fieldRect.size,
                        ),
                      ),
                    ),
                    // 지도 앱처럼 도시 이름만 확대 단계별로 표시(항구 점 라벨은
                    // 제거해 깔끔하게). 지역 선택은 우측 상단 지역 선택 버튼으로 한다.
                    MapCityLabelLayer(projection: projection, scale: _scale),
                    // 예보 표가 열려 있으면 그 지점에 윈디식 방향 나침반(로즈)을,
                    // 아니면 탭한 지점에 "이 지점의 예보" 말풍선을 띄운다.
                    if (widget.forecastPoint case final fp?)
                      ValueListenableBuilder<HourlyMarine?>(
                        valueListenable: widget.roseHour,
                        builder: (context, hour, _) => hour == null
                            ? const SizedBox.shrink()
                            : _ForecastRose(
                                scale: _scale,
                                left: projection.x(fp.longitude),
                                top: projection.y(fp.latitude),
                                hour: hour,
                              ),
                      )
                    else if (_pickedLat case final plat?)
                      if (_pickedLon case final plon?)
                        _PointCallout(
                          scale: _scale,
                          left: projection.x(plon),
                          top: projection.y(plat),
                          onTap: () => widget.onForecast(plat, plon),
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

/// 지도 위에 겹쳐 뜨는 하단 바: 풍속 범례 + 시간 스크러버(지도 애니메이션
/// 시각 제어) + 선택 지점 요약. 요약을 탭하면 그 지점의 2주 예보 표로 들어간다.
class _BottomInfoBar extends ConsumerWidget {
  const _BottomInfoBar({
    required this.selected,
    required this.times,
    required this.hourOffset,
    required this.onHourChanged,
    required this.onOpenForecast,
  });

  final SeaLocation selected;
  final List<DateTime> times;
  final int hourOffset;
  final ValueChanged<int> onHourChanged;
  final VoidCallback onOpenForecast;

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
              onTap: onOpenForecast,
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
                        const Icon(Icons.table_rows_outlined),
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
    required this.onTap,
  });

  final double scale;
  final double left;
  final double top;
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

/// 선택 지점 위에 뜨는 윈디식 방향 나침반. 가운데 점을 중심으로 바람·너울·
/// 너울2가 각자 진행 방향으로 뻗는 **가늘고 긴 색 막대**로 그리고, 글자를
/// 막대 안에 넣어(작은 글씨) 막대끼리 가까워도 서로 가려지지 않게 한다.
/// 지도를 확대해도 크기가 일정하도록 반대로 축소한다.
class _ForecastRose extends StatelessWidget {
  const _ForecastRose({
    required this.scale,
    required this.left,
    required this.top,
    required this.hour,
  });

  final double scale;
  final double left;
  final double top;
  final HourlyMarine hour;

  static const double _len = 96; // 막대 길이(중심→끝)
  static const double _thick = 15; // 막대 두께(글자가 들어갈 만큼만)
  static const double _d = 240; // 로즈 박스 한 변
  static const Offset _c = Offset(_d / 2, _d / 2);

  static const _windC = Color(0xFF3FB6DC);
  static const _swellC = Color(0xFFEB963A);
  static const _swell2C = Color(0xFF7CB342);

  @override
  Widget build(BuildContext context) {
    final bars = <({double dir, Color color, String label, String value})>[
      (
        dir: hour.windDirectionDeg,
        color: _windC,
        label: '바람',
        value: '${hour.windSpeedMs.round()}m/s',
      ),
      (
        dir: hour.swellDirectionDeg,
        color: _swellC,
        label: '너울',
        value:
            '${hour.swellHeightM.toStringAsFixed(1)}m·${hour.swellPeriodS.round()}s',
      ),
      (
        dir: hour.swell2DirectionDeg,
        color: _swell2C,
        label: '너울2',
        value:
            '${hour.swell2HeightM.toStringAsFixed(1)}m·${hour.swell2PeriodS.round()}s',
      ),
    ];
    return Positioned(
      left: left,
      top: top,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.scale(
          scale: 1 / scale,
          alignment: Alignment.center,
          child: SizedBox(
            width: _d,
            height: _d,
            child: Stack(
              children: [
                CustomPaint(
                  size: const Size(_d, _d),
                  painter: _RoseRingPainter(center: _c),
                ),
                for (final b in bars) _bar(b.dir, b.color, b.label, b.value),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 진행(불어가는) 방향(dir+180)으로 뻗는 가늘고 긴 캡슐 막대. 글자를 막대
  /// 안에 넣고, 막대가 어느 방향이든 글씨가 뒤집히지 않도록 캡슐 중심을
  /// 축으로 필요하면 180° 돌려 항상 바로 읽히게 한다(막대 위치는 그대로).
  Widget _bar(double dirDeg, Color color, String label, String value) {
    final rad = (dirDeg + 180) * math.pi / 180;
    final u = Offset(math.sin(rad), -math.cos(rad)); // 화면상 진행 방향 단위벡터
    final mid = _c + u * (_len / 2); // 캡슐 중심(중심→끝 구간의 중점)
    var angle = math.atan2(u.dy, u.dx); // 캡슐 장축의 화면 각도
    // 글씨가 위를 향하도록: 왼쪽(cos<0)으로 향하면 같은 직선 위에서 180° 회전.
    var flip = false;
    if (math.cos(angle) < 0) {
      angle += math.pi;
      flip = true;
    }
    return Positioned(
      left: mid.dx,
      top: mid.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(
          angle: angle,
          child: Container(
            width: _len,
            height: _thick,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(_thick / 2),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 2),
              ],
            ),
            // 뒤집힌 경우 라벨이 바깥쪽에 오도록 순서를 뒤집는다.
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              textDirection: flip ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 나침반의 반투명 원 + 가운데 점만 그린다(막대는 위젯으로 얹는다).
class _RoseRingPainter extends CustomPainter {
  _RoseRingPainter({required this.center});

  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      center,
      _ForecastRose._len,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(center, 5, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      5,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_RoseRingPainter old) => old.center != center;
}

/// 파고/너울 높이(m) → 색상. 낮음(청록) → 높음(분홍/자주)으로 이어지는
/// 윈디식 스케일. 바람은 [windSpeedColor]를 쓰고 파도 계열은 이 함수를 쓴다.
Color waveHeightColor(double m) {
  final t = (m / 3.0).clamp(0.0, 1.0);
  return HSVColor.fromAHSV(1, 200 + 130 * t, 0.55, 0.9).toColor();
}

Color _readableOn(Color bg) =>
    bg.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;

/// forecast at this point 패널. "이 지점의 예보"를 누르면 바로 뜨는 2주
/// 시간별 색상 표(윈디식 메테오그램). 상단에 시간 슬라이더를 두어 그래픽을
/// 강화하고, 표는 하단에 붙여 3시간 간격으로 향후 2주를 가로 스크롤로 본다.
/// 바람·돌풍·파도·너울에 색을 입혀 세기를 직관적으로 느낄 수 있게 한다.
class _PointForecastPanel extends ConsumerStatefulWidget {
  const _PointForecastPanel({
    required this.location,
    required this.roseHour,
    required this.onClose,
  });

  final SeaLocation location;

  /// 선택 중인 시각의 해양값을 지도 위 방향 나침반에 전달하는 통로.
  final ValueNotifier<HourlyMarine?> roseHour;
  final VoidCallback onClose;

  @override
  ConsumerState<_PointForecastPanel> createState() =>
      _PointForecastPanelState();
}

class _PointForecastPanelState extends ConsumerState<_PointForecastPanel> {
  int _i = 0;
  int _stepCount = 0;
  bool _syncingFromSlider = false;
  bool _initialized = false;
  final ScrollController _hCtrl = ScrollController();

  /// [steps] 중 현재 시각과 가장 가까운 칸의 인덱스.
  int _closestToNow(List<HourlyMarine> steps) {
    final now = DateTime.now();
    var best = 0;
    var bestDiff = const Duration(days: 999);
    for (var k = 0; k < steps.length; k++) {
      final d = steps[k].time.difference(now).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = k;
      }
    }
    return best;
  }

  static const double _colW = 46;
  static const double _labelW = 62;
  static const double _dayH = 22;
  static const double _timeH = 20;
  static const double _cellH = 23;

  /// 슬라이더가 표를 스크롤할 때 화면 왼쪽에서 선택 열까지 띄우는 여백(px).
  static const double _selectPad = 120;

  @override
  void initState() {
    super.initState();
    _hCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _hCtrl.removeListener(_onScroll);
    _hCtrl.dispose();
    super.dispose();
  }

  /// 표를 가로로 스크롤하면 위 슬라이더도 따라오게 한다(표 → 슬라이더 연동).
  void _onScroll() {
    if (_syncingFromSlider || !_hCtrl.hasClients || _stepCount == 0) return;
    final idx = ((_hCtrl.offset + _selectPad) / _colW).round().clamp(
      0,
      _stepCount - 1,
    );
    if (idx != _i) setState(() => _i = idx);
  }

  /// 슬라이더 → 표 연동. 스크롤 애니메이션 동안 [_onScroll]이 값을 되돌리지
  /// 않도록 플래그로 막는다.
  void _scrollToSelected() {
    if (!_hCtrl.hasClients) return;
    final target = (_i * _colW - _selectPad).clamp(
      0.0,
      _hCtrl.position.maxScrollExtent,
    );
    _syncingFromSlider = true;
    _hCtrl
        .animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        )
        .whenComplete(() => _syncingFromSlider = false);
  }

  @override
  Widget build(BuildContext context) {
    final forecastAsync = ref.watch(marineForecastProvider(widget.location));
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 16)],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Icon(Icons.location_on, size: 18, color: scheme.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '이 지점의 예보  ·  ${widget.location.name}',
                      style: Theme.of(context).textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close),
                    tooltip: '지도로 돌아가기',
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            forecastAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (e, _) => const Padding(
                padding: EdgeInsets.all(16),
                child: Text('예보를 불러오지 못했습니다'),
              ),
              data: (forecast) {
                // 3시간 간격으로 향후 최대 16일(Open-Meteo 예보 상한)을 뽑는다.
                final steps = [
                  for (final h in forecast.hourly)
                    if (h.time.hour % 3 == 0) h,
                ].take(16 * 8).toList();
                if (steps.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('예보 데이터가 없습니다.'),
                  );
                }
                _stepCount = steps.length;
                final nowIdx = _closestToNow(steps);
                // 진입 시 현재 시각과 가장 가까운 칸에 위치시키고 그리로 스크롤.
                if (!_initialized) {
                  _initialized = true;
                  _i = nowIdx;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _scrollToSelected();
                  });
                }
                final i = _i.clamp(0, steps.length - 1);
                final at = steps[i];
                final atIsNow = i == nowIdx;
                // 지도 위 방향 나침반이 이 선택 시각을 반영하도록 전달한다.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) widget.roseHour.value = at;
                });
                return Column(
                  children: [
                    // 상단 시간 슬라이더(그래픽 강화). 선택 시각을 크게 강조하고,
                    // 현재 시각이면 "지금" 배지를 붙여 잘 보이게 한다.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Icon(Icons.schedule, size: 18, color: scheme.primary),
                          const SizedBox(width: 6),
                          if (atIsNow)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '지금',
                                style: TextStyle(
                                  color: scheme.onPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          Text(
                            '${formatMonthDay(at.time)} ${formatHm(at.time)}',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Slider(
                              value: i.toDouble(),
                              min: 0,
                              max: (steps.length - 1).toDouble(),
                              onChanged: (v) {
                                setState(() => _i = v.round());
                                _scrollToSelected();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    _Meteogram(
                      steps: steps,
                      selected: i,
                      nowIndex: nowIdx,
                      controller: _hCtrl,
                      onColumnTap: (j) => setState(() => _i = j),
                    ),
                    const SizedBox(height: 4),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 윈디식 색상 메테오그램: 왼쪽 항목 열 고정 + 오른쪽 시각 열 가로 스크롤.
class _Meteogram extends StatelessWidget {
  const _Meteogram({
    required this.steps,
    required this.selected,
    required this.nowIndex,
    required this.controller,
    required this.onColumnTap,
  });

  final List<HourlyMarine> steps;
  final int selected;
  final int nowIndex;
  final ScrollController controller;
  final ValueChanged<int> onColumnTap;

  @override
  Widget build(BuildContext context) {
    const rows = [
      '시간',
      '날씨',
      '기온 °C',
      '바람 m/s',
      '돌풍 m/s',
      '너울 m',
      '너울2 m',
      '파력 kW/m',
      '수온 °C',
    ];
    final labelStyle = Theme.of(context).textTheme.bodySmall;
    final totalH =
        _PointForecastPanelState._dayH +
        _PointForecastPanelState._timeH +
        _PointForecastPanelState._cellH * (rows.length - 1);
    return SizedBox(
      height: totalH,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 왼쪽 항목 라벨(맨 위 날짜 행만큼 띄운다).
          SizedBox(
            width: _PointForecastPanelState._labelW,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const SizedBox(height: _PointForecastPanelState._dayH),
                for (var r = 0; r < rows.length; r++)
                  SizedBox(
                    height: r == 0
                        ? _PointForecastPanelState._timeH
                        : _PointForecastPanelState._cellH,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(rows[r], style: labelStyle),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: controller,
              scrollDirection: Axis.horizontal,
              itemCount: steps.length,
              itemBuilder: (context, j) {
                final isNewDay =
                    j == 0 ||
                    !DateUtils.isSameDay(steps[j].time, steps[j - 1].time);
                return _MeteogramColumn(
                  hour: steps[j],
                  isNewDay: isNewDay,
                  isSelected: j == selected,
                  isNow: j == nowIndex,
                  onTap: () => onColumnTap(j),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MeteogramColumn extends StatelessWidget {
  const _MeteogramColumn({
    required this.hour,
    required this.isNewDay,
    required this.isSelected,
    required this.isNow,
    required this.onTap,
  });

  final HourlyMarine hour;
  final bool isNewDay;
  final bool isSelected;
  final bool isNow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final windC = windSpeedColor(hour.windSpeedMs);
    final gustC = windSpeedColor(hour.windGustMs);
    final swellC = waveHeightColor(hour.swellHeightM);
    final swell2C = waveHeightColor(hour.swell2HeightM);
    final isNight = hour.time.hour < 6 || hour.time.hour >= 19;

    Widget cell(
      String text, {
      Color? bg,
      double h = _PointForecastPanelState._cellH,
    }) => Container(
      width: _PointForecastPanelState._colW,
      height: h,
      alignment: Alignment.center,
      color: bg,
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: bg == null ? null : _readableOn(bg),
          fontWeight: bg == null ? FontWeight.normal : FontWeight.w600,
        ),
      ),
    );

    // 방향 화살촉 + 숫자를 한 칸에 함께 그린다(바람·WIND·SWELL·SWELL2).
    Widget arrowCell(String text, double dirDeg, {required Color bg}) {
      final fg = _readableOn(bg);
      return Container(
        width: _PointForecastPanelState._colW,
        height: _PointForecastPanelState._cellH,
        color: bg,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DirectionArrow(directionDeg: dirDeg, size: 9, color: fg),
            const SizedBox(width: 2),
            Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            // 현재 시각 칸은 왼쪽 테두리를 굵은 강조색으로.
            left: BorderSide(
              color: isNow
                  ? scheme.primary
                  : (isNewDay ? scheme.outline : scheme.outlineVariant),
              width: isNow ? 2.4 : (isNewDay ? 1.2 : 0.4),
            ),
          ),
          color: isSelected
              ? scheme.primary.withValues(alpha: 0.14)
              : (isNow ? scheme.primary.withValues(alpha: 0.06) : null),
        ),
        child: Column(
          children: [
            // 상단 행: 현재 시각이면 "지금" 배지, 아니면 새 날짜.
            SizedBox(
              height: _PointForecastPanelState._dayH,
              width: _PointForecastPanelState._colW,
              child: isNow
                  ? Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '지금',
                          style: TextStyle(
                            color: scheme.onPrimary,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  : (isNewDay
                        ? Center(
                            child: Text(
                              '${hour.time.month}/${hour.time.day}',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          )
                        : null),
            ),
            cell('${hour.time.hour}', h: _PointForecastPanelState._timeH),
            // 날씨 아이콘(맑음·구름·비·번개 등).
            SizedBox(
              width: _PointForecastPanelState._colW,
              height: _PointForecastPanelState._cellH,
              child: Center(
                child: WeatherIcon(
                  code: hour.weatherCode,
                  size: _PointForecastPanelState._cellH - 4,
                  night: isNight,
                ),
              ),
            ),
            cell('${hour.airTempC.round()}'),
            arrowCell(
              '${hour.windSpeedMs.round()}',
              hour.windDirectionDeg,
              bg: windC,
            ),
            cell(
              '${hour.windGustMs.round()}',
              bg: gustC.withValues(alpha: 0.65),
            ),
            arrowCell(
              hour.swellHeightM.toStringAsFixed(1),
              hour.swellDirectionDeg,
              bg: swellC.withValues(alpha: 0.85),
            ),
            arrowCell(
              hour.swell2HeightM.toStringAsFixed(1),
              hour.swell2DirectionDeg,
              bg: swell2C.withValues(alpha: 0.7),
            ),
            cell(formatWavePower(hour.wavePowerKw)),
            cell('${hour.waterTempC.round()}'),
          ],
        ),
      ),
    );
  }
}
