import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_tab_provider.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/kst.dart';
import '../../locations/data/models/sea_location.dart';
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
/// 진입 시 지도만 전체 화면으로 보인다(핀치 줌 가능). 지도를 탭하면 그 지점에
/// 핀이 꽂히고, 상단에 그 지점의 바람 세기·방향과 "상세 예보" 버튼이 뜬다.
/// "상세 예보"를 누르면 하단에 임의 좌표의 시간별 예보 표(forecast at this
/// point)가 펼쳐지고, 지도의 그 지점에는 방향 나침반(WIND/SWELL/SWELL2)이
/// 그려진다. back 키를 누르면 표를 닫고 지도로 돌아간다.
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

  /// 예보 표에서 선택 중인 시각의 해양값 — 지도 위 방향 나침반과 공유하고,
  /// 지도 바람장(히트맵·파티클)도 이 시각을 따라간다.
  final ValueNotifier<HourlyMarine?> _roseHour = ValueNotifier(null);
  WindFieldSeries? _series;

  /// 지도에 그릴 바람장 시각 인덱스. 기본은 현재 시각이고, 상세 예보의
  /// 슬라이더로 시각을 고르면 지도도 그 시각의 바람으로 바뀐다(윈디처럼).
  int _hourOffset = 0;

  /// 상세 예보로 켜진 지점. null이면 지도 모드(하단 표 없음).
  SeaLocation? _forecastPoint;

  /// 지도에서 탭한 커서 좌표. null이면 아직 안 찍음(진입 시 지도만 보인다).
  double? _cursorLat;
  double? _cursorLon;

  /// 하단 바(시간 슬라이더 또는 상세 예보 표)가 차지하는 높이. 오른쪽 세로
  /// 아이콘 내비게이션을 이 높이만큼 위로 올려, 표가 떴을 때 겹치지 않게 한다.
  final GlobalKey _bottomBarKey = GlobalKey();
  double _bottomBarHeight = 0;

  void _measureBottomBar() {
    final h = _bottomBarKey.currentContext?.size?.height ?? 0;
    if ((h - _bottomBarHeight).abs() > 0.5 && mounted) {
      setState(() => _bottomBarHeight = h);
    }
  }

  void _onPick(double lat, double lon) {
    setState(() {
      _cursorLat = lat;
      _cursorLon = lon;
      // 상세 예보가 열려 있으면 그 지점으로 실시간 갱신(날짜 위치는 패널이 유지).
      if (_forecastPoint != null) {
        _forecastPoint = pointSeaLocation(lat, lon);
      }
    });
  }

  void _openDetail() {
    final lat = _cursorLat;
    final lon = _cursorLon;
    if (lat == null || lon == null) return;
    setState(() => _forecastPoint = pointSeaLocation(lat, lon));
  }

  /// 상단 커서 바의 X — 찍은 지점을 지워 바를 없앤다.
  void _clearCursor() {
    setState(() {
      _cursorLat = null;
      _cursorLon = null;
    });
  }

  void _closeDetail() {
    _roseHour.value = null;
    setState(() {
      _forecastPoint = null;
      // 표를 닫으면 지도를 다시 현재 시각(서울 기준) 바람으로 되돌린다.
      final series = _series;
      if (series != null) {
        _hourOffset = series.indexClosestTo(nowKst());
      }
    });
  }

  /// 지도 모드 하단 슬라이더로 바람장 시각을 바꾼다.
  void _setMapHour(int idx) {
    if (idx != _hourOffset) setState(() => _hourOffset = idx);
  }

  /// 지도 시각을 다시 "지금"(서울 기준)으로 되돌린다.
  void _mapHourToNow() {
    final series = _series;
    if (series == null) return;
    final idx = series.indexClosestTo(nowKst());
    if (idx != _hourOffset) setState(() => _hourOffset = idx);
  }

  // Windy 화면녹화와 프레임 단위로 비교한 결과에 맞춘다: Windy는 **짧고 빠른**
  // 흐름선이 **더 촘촘히**(흰 픽셀 비율 ~1.04% vs 우리 0.80%) 흐른다. 그래서
  // 개수를 1700으로 늘리고 궤적은 짧게(유성 꼬리보다 Windy식 짧은 선) 잡는다.
  // 궤적이 짧아 세그먼트 총수는 오히려 v0.1.39(1200×긴꼬리)보다 적어 더 가볍다
  // (렌더는 단계별 drawRawPoints로 파티클수와 무관하게 캔버스 콜 상수).
  static const _particleCount = 1700;
  static const _maxAgeSeconds = 20.0;

  /// 궤적 길이(포인트 수)를 풍속에 비례해 늘린다(윈디식 잔상). Windy처럼 짧게
  /// (최대 34) 잡아 짧고 빠른 흐름선이 많이 흐르는 느낌을 낸다.
  static const _minTrail = 9;
  static const _maxTrailCap = 34;
  static const _trailSpeedFactor = 3.0;

  /// 위경도 이동 배율(도/초 per m/s) — 화면 안 흐름선의 이동 "속도"를 정하는
  /// 시각적 배율이며 실제 지리 이동 속도가 아니다. Windy의 초당 화면변화가
  /// 약 2배라, 이동을 더 또렷하게 0.24로 올린다(이전 0.18).
  static const _degreesPerMps = 0.24;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _roseHour.addListener(_syncMapHour);
  }

  /// 상세 예보 슬라이더가 고른 시각으로 지도 바람장을 맞춘다.
  void _syncMapHour() {
    final series = _series;
    final hour = _roseHour.value;
    if (series == null || hour == null) return;
    final idx = series.indexClosestTo(hour.time);
    if (idx != _hourOffset && mounted) {
      setState(() => _hourOffset = idx);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    _roseHour.removeListener(_syncMapHour);
    _roseHour.dispose();
    super.dispose();
  }

  void _ensureSeeded(WindFieldSeries series) {
    if (_series != null) return;
    _series = series;
    // 시계열은 오늘 0시(서울)부터 시작하므로, 지도 기본 시각을 서울 기준
    // "지금"에 맞춘다(기기 시간대 설정과 무관).
    _hourOffset = series.indexClosestTo(nowKst());
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
    var dt = _lastElapsed == Duration.zero
        ? 1 / 60
        : (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (dt <= 0) return;
    // 예전엔 dt>0.25면 통째로 스킵했는데, 프레임이 무거워지면 매 틱 스킵돼
    // 파티클이 "얼어" 바람 이동이 안 보였다(성능 저하의 증상이 정지로 나타남).
    // 스킵 대신 한 스텝 상한(0.05초)만 둬서, 느린 프레임/백그라운드 복귀에도
    // 큰 점프 없이 조금씩이라도 계속 흐르게 한다.
    if (dt > 0.05) dt = 0.05;

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

    // back 키: 상세 예보가 열려 있으면 먼저 지도로 돌아간다(앱 종료 대신).
    return PopScope(
      canPop: _forecastPoint == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _forecastPoint != null) _closeDetail();
      },
      child: Scaffold(
        // 상단 앱바 없이 지도를 전체 화면으로(윈디식 몰입형). 컨트롤은 지도
        // 위에 투명하게 떠 있다.
        body: seriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('바람장을 불러오지 못했습니다: $e')),
          data: (result) {
            final series = result.series;
            _ensureSeeded(series);
            final field = series.at(_hourOffset);

            // 커서(탭한 지점)의 바람 세기·방향(상단 표시용). u/v는 흐름 방향
            // 성분이므로, 불어오는 방향(기상 관례)은 atan2(-u,-v)로 되돌린다.
            double? cSpeed;
            double? cDir;
            if (_cursorLat case final clat?) {
              if (_cursorLon case final clon?) {
                final uv = field.sample(clat, clon);
                if (uv != null) {
                  final (u, v) = uv;
                  cSpeed = math.sqrt(u * u + v * v);
                  cDir = (math.atan2(-u, -v) * 180 / math.pi + 360) % 360;
                }
                // 격자(약 2° 간격) 보간은 국지 바람이 뭉개져 실제(윈디 지점
                // 표시값)보다 약하게 나온다. 정확한 좌표로 요청한 지점 시계열이
                // 도착하면, 지도에 표시 중인 시각과 같은 시각의 지점값으로
                // 덮어써 윈디와 숫자가 맞게 한다(도착 전엔 격자값 폴백).
                final points = ref
                    .watch(
                      cursorWindSeriesProvider((
                        lat: (clat * 1000).roundToDouble() / 1000,
                        lon: (clon * 1000).roundToDouble() / 1000,
                      )),
                    )
                    .valueOrNull;
                if (points != null && points.isNotEmpty) {
                  var best = points.first;
                  var bestDiff = best.time.difference(field.time).abs();
                  for (final p in points) {
                    final d = p.time.difference(field.time).abs();
                    if (d < bestDiff) {
                      bestDiff = d;
                      best = p;
                    }
                  }
                  cSpeed = best.speedMs;
                  cDir = best.directionDeg;
                }
              }
            }

            // 하단 바 높이를 렌더 뒤 측정해 오른쪽 아이콘 내비를 그 위로 올린다.
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _measureBottomBar(),
            );

            return Stack(
              children: [
                Positioned.fill(
                  child: _WindMapArea(
                    field: field,
                    particles: _particles,
                    repaint: _repaint,
                    forecastPoint: _forecastPoint,
                    roseHour: _roseHour,
                    cursorLat: _cursorLat,
                    cursorLon: _cursorLon,
                    onPick: _onPick,
                    onOpenDetail: _openDetail,
                    bottomBarHeight: _bottomBarHeight,
                  ),
                ),
                // 상단: 상세 예보 진입 전, 커서 지점의 바람 세기·방향 + 진입 버튼.
                if (_forecastPoint == null && cSpeed != null && cDir != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _CursorWindBar(
                      speed: cSpeed,
                      dir: cDir,
                      onDetail: _openDetail,
                      onClose: _clearCursor,
                    ),
                  ),
                // 하단(지도 모드): 시간·날짜 슬라이더. 지도만 보이는 상태에서
                // 바람장 시각을 윈디처럼 앞뒤로 스크럽한다.
                if (_forecastPoint == null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: KeyedSubtree(
                      key: _bottomBarKey,
                      child: _MapTimeBar(
                        series: series,
                        offset: _hourOffset,
                        nowOffset: series.indexClosestTo(nowKst()),
                        synthetic: result.isSynthetic,
                        onChanged: _setMapHour,
                        onNow: _mapHourToNow,
                      ),
                    ),
                  ),
                // 하단: 상세 예보 표(열렸을 때만).
                if (_forecastPoint case final fp?)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: KeyedSubtree(
                      key: _bottomBarKey,
                      child: _PointForecastPanel(
                        location: fp,
                        roseHour: _roseHour,
                        onClose: _closeDetail,
                      ),
                    ),
                  ),
                // 오른쪽 세로 아이콘 내비게이션(Windy 탭 전용). 하단 바 높이만큼
                // 위로 올려 시간 바·상세 예보 표와 겹치지 않게 한다.
                Positioned(
                  right: 2,
                  bottom: _bottomBarHeight + 2,
                  child: _WindyNavRail(
                    onSelect: (i) =>
                        ref.read(appTabIndexProvider.notifier).state = i,
                  ),
                ),
              ],
            );
          },
        ),
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
    required this.cursorLat,
    required this.cursorLon,
    required this.onPick,
    required this.onOpenDetail,
    required this.bottomBarHeight,
  });

  final WindField field;
  final List<WindParticle> particles;

  /// 매 프레임 파티클 레이어만 다시 그리게 하는 리페인트 신호.
  final Listenable repaint;

  /// 현재 예보 모드로 켜진 지점(있으면 그 지점에 방향 나침반을 그린다).
  final SeaLocation? forecastPoint;

  /// 하단 바(시간 슬라이더 또는 상세 예보 표)의 현재 높이. 상세 예보를 열 때
  /// 이 높이만큼 뺀 "실제로 보이는" 영역 가운데에 탭 지점이 오도록 지도를
  /// 다시 중앙 정렬하는 데 쓴다.
  final double bottomBarHeight;

  /// 방향 나침반에 표시할 현재 선택 시각의 해양값(예보 표와 공유).
  final ValueNotifier<HourlyMarine?> roseHour;

  /// 탭한 커서 좌표(상위 화면이 소유). null이면 아직 안 찍음.
  final double? cursorLat;
  final double? cursorLon;

  /// 지도를 탭했을 때 커서 좌표를 알린다.
  final void Function(double lat, double lon) onPick;

  /// "상세 예보" 말풍선 → 커서 지점 예보 표로 진입.
  final VoidCallback onOpenDetail;

  @override
  State<_WindMapArea> createState() => _WindMapAreaState();
}

class _WindMapAreaState extends State<_WindMapArea> {
  ui.Image? _heatmap;

  /// 한반도 핵심영역([_coreBounds])만 따로 촘촘하게 구운 고해상도 래스터.
  /// 전체 bbox 래스터는 남한을 ~63×62px로만 담아 확대 시 뭉개지므로, 이
  /// 오버레이가 실제 보이는 디테일을 책임진다([WindHeatmapPainter]가 배경
  /// 위에 덧그림).
  ui.Image? _heatmapCore;
  DateTime? _heatmapTime;

  /// 진행 중인 히트맵 빌드의 최신성 토큰 — 시간 스크럽 등으로 빌드가 겹치면
  /// 낡은 결과를 버린다(시간 비교만으로는 같은 시각의 재빌드 경쟁을 못 거름).
  int _heatmapRequestId = 0;

  /// 고해상도 오버레이 범위: 남한 전역 + 서해·남해·동해·대한해협·규슈 연안.
  /// 약 50px/°로 구워 전체 bbox 래스터(10.5px/°)의 5배² 밀도.
  static const _coreBounds = LatLonBounds(
    minLat: 28.0,
    maxLat: 44.0,
    minLon: 116.0,
    maxLon: 138.0,
  );
  static const _coreTexW = 1100;
  static const _coreTexH = 800;

  final TransformationController _transformController =
      TransformationController();
  // 지도 범위를 동서남북으로 넓힌 만큼, 진입 기본 배율도 조금 올려 남한이
  // 이전과 비슷한 크기로 보이게 한다.
  double _scale = 2.1;

  /// 사용자가 지도를 직접 조작(팬/줌)했는지. 하기 전까지는 매 build마다
  /// 남한 중앙 기본 위치를 다시 적용한다 — 앱 시작 직후 시스템 인셋이
  /// 정착하기 전의 일시적 레이아웃 크기로 중심이 계산·고정돼 서해가
  /// 가운데로 오던 버그의 수정(1회성 플래그로는 첫 잘못된 값이 박제됨).
  bool _userInteracted = false;

  /// "남한 중앙" 기준점(대전 인근) — 진입 시, 그리고 상세 예보를 닫아
  /// 지도 모드로 돌아올 때 항상 이 위경도가 화면 정가운데에 오게 한다.
  /// 상세 예보 중엔 탭한 지점이 중앙에 오도록 [_centerOnPoint]가 대신
  /// 화면을 옮기므로(하단 표 높이만큼 세로 중심도 달라짐), 표를 닫으면
  /// 이 기본 위치로 되돌려야 다음에 지도만 볼 때도 항상 남한이 가운데다.
  static const _defaultCenterLon = 127.8;
  static const _defaultCenterLat = 36.3;
  static const _defaultScale = 2.1;
  // 라벨 후보를 "현재 화면에 보이는 범위"로 좁히는 데 쓰는, 마지막으로
  // rebuild를 트리거한 시점의 이동량(child 좌표계, 즉 mapSize 기준 px).
  Offset _lastLabelTranslation = Offset.zero;
  // 상세 예보를 열 때 탭 지점을 다시 중앙 정렬하는 데 쓰려고 build()에서
  // 캐싱해 두는 최근 레이아웃 크기(화면 크기·지도 캔버스 크기는 didUpdateWidget
  // 시점엔 LayoutBuilder 밖이라 직접 구할 수 없어 이렇게 저장해 둔다).
  Size? _lastScreen;
  Size? _lastMapSize;

  @override
  void initState() {
    super.initState();
    _rebuildHeatmap();
    _transformController.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    final m = _transformController.value;
    final newScale = m.getMaxScaleOnAxis();
    final t = m.getTranslation();
    final translation = Offset(t.x, t.y);
    // 확대뿐 아니라 **이동(팬)도** 일정량 이상이면 다시 그린다 — 안 그러면
    // 화면에 보이는 지역이 바뀌어도 라벨 후보(뷰포트 기준 필터)가 갱신되지
    // 않는다. 임계값을 둬 드래그 중 매 프레임 rebuild하지 않게 한다.
    final scaleChanged = (newScale - _scale).abs() > 0.02;
    // 팬은 드래그 중 프레임마다 계속 바뀌므로 문턱을 넉넉히 둬(스케일보다
    // 훨씬 큼) 드래그 내내 매 프레임 rebuild하지 않게 한다 — 라벨 갱신은
    // 드래그가 어느 정도 진행되거나 멈춘 뒤 반영돼도 충분하다.
    final panChanged = (translation - _lastLabelTranslation).distance > 120;
    if (scaleChanged || panChanged) {
      _lastLabelTranslation = translation;
      setState(() => _scale = newScale);
    }
  }

  @override
  void didUpdateWidget(covariant _WindMapArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.field.time != _heatmapTime) {
      _rebuildHeatmap();
    }
    // 상세 예보를 새로 열었거나(새 지점 탭 포함) 하단 표 높이가 막
    // 확정됐으면(패널 종류가 바뀌어 높이가 달라지는 첫 프레임엔 아직 이전
    // 값이라 한 프레임 늦게 다시 옴), 그 지점이 표를 뺀 화면 가운데에
    // 오도록 지도를 다시 중앙 정렬한다.
    final fp = widget.forecastPoint;
    if (fp != null &&
        (fp != oldWidget.forecastPoint ||
            (widget.bottomBarHeight - oldWidget.bottomBarHeight).abs() > 0.5)) {
      _centerOnPoint(fp.latitude, fp.longitude);
    } else if (fp == null && oldWidget.forecastPoint != null) {
      // 상세 예보를 닫아 지도 모드로 돌아왔다 — 탭한 지점 중심으로 옮겨져
      // 있던 화면을 남한 중앙 기본 위치로 되돌린다.
      _resetToDefaultCenter();
    }
  }

  /// 진입 시, 그리고 상세 예보를 닫을 때 남한 중앙을 화면 가운데 두고
  /// 기본 배율로 되돌린다.
  void _resetToDefaultCenter() {
    final screen = _lastScreen;
    final mapSize = _lastMapSize;
    if (screen == null || mapSize == null) return;
    final projection = MapProjection(mapViewBounds, mapSize);
    final kx = projection.x(_defaultCenterLon);
    final ky = projection.y(_defaultCenterLat);
    _transformController.value = Matrix4.identity()
      ..translate(
        screen.width / 2 - _defaultScale * kx,
        screen.height / 2 - _defaultScale * ky,
      )
      ..scale(_defaultScale);
  }

  /// (lat, lon)이 하단 바를 뺀 화면 영역 가운데에 오도록 현재 배율은 유지한
  /// 채 지도를 다시 중앙 정렬한다.
  void _centerOnPoint(double lat, double lon) {
    final screen = _lastScreen;
    final mapSize = _lastMapSize;
    if (screen == null || mapSize == null) return;
    final projection = MapProjection(mapViewBounds, mapSize);
    final s = _scale <= 0 ? 1.0 : _scale;
    final kx = projection.x(lon);
    final ky = projection.y(lat);
    final visibleH = (screen.height - widget.bottomBarHeight).clamp(
      1.0,
      screen.height,
    );
    final targetCx = screen.width / 2;
    final targetCy = visibleH / 2;
    _transformController.value = Matrix4.identity()
      ..translate(targetCx - s * kx, targetCy - s * ky)
      ..scale(s);
  }

  Future<void> _rebuildHeatmap() async {
    final field = widget.field;
    final time = field.time;
    final requestId = ++_heatmapRequestId;
    // 데이터 없는 시각(u/v가 전부 0으로 채워진 결측 스텝)은 색을 입히면
    // "무풍(보라색)"으로 오해되므로, 아예 히트맵을 만들지 않고 build()가
    // 회색 오버레이를 그리게 한다.
    if (!field.hasData) {
      _heatmap?.dispose();
      _heatmapCore?.dispose();
      setState(() {
        _heatmap = null;
        _heatmapCore = null;
        _heatmapTime = time;
      });
      return;
    }
    // 전체 bbox 배경(작고 빠름)을 먼저 띄우고, 핵심영역 고해상도는 이어서.
    final image = await buildWindHeatmapImage(field);
    if (!mounted || requestId != _heatmapRequestId) {
      image.dispose();
      return;
    }
    _heatmap?.dispose();
    setState(() {
      _heatmap = image;
      _heatmapTime = time;
    });
    final core = await buildWindHeatmapImage(
      field,
      crop: _coreBounds,
      width: _coreTexW,
      height: _coreTexH,
    );
    if (!mounted || requestId != _heatmapRequestId) {
      core.dispose();
      return;
    }
    _heatmapCore?.dispose();
    setState(() => _heatmapCore = core);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    _heatmap?.dispose();
    _heatmapCore?.dispose();
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
          final screen = constraints.biggest;
          final heatmap = _heatmap;
          // 실물 비율(위·경도 왜곡 보정): 위도 1° ≈ 경도 1°×cos(위도)이므로,
          // 지도 캔버스의 가로:세로를 (경도폭×cos):(위도폭)로 잡아 세로로
          // 늘어나 보이던 왜곡을 없앤다. 화면을 가득 덮도록(cover) 크기를 잡아
          // 남는 한 방향은 넘쳐서(pan) 볼 수 있게 한다.
          final centerLat = (mapViewBounds.minLat + mapViewBounds.maxLat) / 2;
          final cosLat = math.cos(centerLat * math.pi / 180);
          final lonSpan = mapViewBounds.maxLon - mapViewBounds.minLon;
          final latSpan = mapViewBounds.maxLat - mapViewBounds.minLat;
          final aspect = (lonSpan * cosLat) / latSpan; // 가로/세로
          var mapW = screen.width;
          var mapH = mapW / aspect;
          if (mapH < screen.height) {
            mapH = screen.height;
            mapW = mapH * aspect;
          }
          final mapSize = Size(mapW, mapH);
          // 상세 예보를 열 때(didUpdateWidget, LayoutBuilder 밖) 재중앙정렬에
          // 쓰려고 최근 레이아웃 크기를 캐싱해 둔다.
          _lastScreen = screen;
          _lastMapSize = mapSize;
          // 모든 레이어가 같은 투영(mapSize 기준)을 공유해 서로 어긋나지 않는다.
          final projection = MapProjection(mapViewBounds, mapSize);
          // 현재 화면에 실제로 보이는 위경도 범위(뷰포트). InteractiveViewer의
          // 변환(이동+배율)을 역산해 화면 네 모서리가 mapSize 좌표계에서
          // 어디에 해당하는지 구한 뒤 위경도로 바꾼다. 라벨 표시 개수 제한이
          // 이 범위 "안"에서만 경쟁하게 해, 깊이 확대해도(먼 지역의 높은
          // 랭크 도시가 예산을 다 써버려 화면엔 아무 라벨도 안 남는 문제 없이)
          // 화면 안의 지역명이 항상 채워지게 한다.
          final tm = _transformController.value;
          final txy = tm.getTranslation();
          final vs = tm.getMaxScaleOnAxis() <= 0 ? 1.0 : tm.getMaxScaleOnAxis();
          Offset toChild(Offset screenPt) =>
              Offset((screenPt.dx - txy.x) / vs, (screenPt.dy - txy.y) / vs);
          final vTopLeft = toChild(Offset.zero);
          final vBottomRight = toChild(Offset(screen.width, screen.height));
          final visibleBounds = LatLonBounds(
            minLat: projection.latFor(
              vBottomRight.dy.clamp(0.0, mapSize.height),
            ),
            maxLat: projection.latFor(vTopLeft.dy.clamp(0.0, mapSize.height)),
            minLon: projection.lonFor(vTopLeft.dx.clamp(0.0, mapSize.width)),
            maxLon: projection.lonFor(
              vBottomRight.dx.clamp(0.0, mapSize.width),
            ),
          );
          final fieldRect = projection.rectFor(
            LatLonBounds(
              minLat: field.minLat,
              maxLat: field.maxLat,
              minLon: field.minLon,
              maxLon: field.maxLon,
            ),
          );
          // 사용자가 지도를 직접 만지기 전까지는 매 레이아웃마다 남한 중앙
          // 기본 위치를 다시 적용한다 — 앱 시작 초기 프레임의 일시적 화면
          // 크기(시스템 인셋 정착 전)로 계산된 중심이 박제되지 않게, 항상
          // "현재" 크기 기준으로 재계산한다(행렬 대입은 멱등이라 부담 없음).
          // 단 상세 예보가 열려 있는 동안은 _centerOnPoint가 맞춘 탭 지점
          // 중심을 존중한다.
          if (!_userInteracted && widget.forecastPoint == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _userInteracted) return;
              _resetToDefaultCenter();
            });
          }
          return InteractiveViewer(
            transformationController: _transformController,
            onInteractionStart: (_) => _userInteracted = true,
            // 캔버스를 화면보다 크게(cover) 잡으므로 constrained를 끈다.
            constrained: false,
            // 완전히 축소해도 지도가 뷰를 덮도록(=검은 여백 없음) 최소 배율을
            // 1보다 살짝 크게 둔다. 정확히 1이면 세로가 뷰 높이에 딱 맞아
            // 세로 팬이 잠기는데(표가 떴을 때 아래로 못 내려가던 원인), 1.15면
            // 항상 약간의 팬 여유가 생겨 잠기지 않으면서도 검은 여백은 없다.
            minScale: 1.15,
            // 섬·소지역 이름·작은 섬까지 보이도록 더 깊게 확대할 수 있게 한다.
            maxScale: 42,
            // 지도가 항상 뷰를 덮으므로 경계 여백은 두지 않는다(가장자리에 검은
            // 빈 부분이 올라오지 않게 한다).
            boundaryMargin: EdgeInsets.zero,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final lat = projection.latFor(details.localPosition.dy);
                final lon = projection.lonFor(details.localPosition.dx);
                if (!field.contains(lat, lon)) return;
                // 커서 좌표를 상위로 알린다. 상세 예보가 열려 있으면 상위에서
                // 그 지점으로 실시간 갱신한다.
                widget.onPick(lat, lon);
              },
              child: SizedBox(
                width: mapSize.width,
                height: mapSize.height,
                child: Stack(
                  children: [
                    if (heatmap != null)
                      CustomPaint(
                        painter: WindHeatmapPainter(
                          image: heatmap,
                          dstRect: fieldRect,
                          coreImage: _heatmapCore,
                          coreDstRect: projection.rectFor(_coreBounds),
                        ),
                        size: mapSize,
                      )
                    else if (!field.hasData)
                      // 모델의 실제 예보 범위를 넘는 시각(예: 요청한 16일 중
                      // 실제로 예보가 없는 마지막 하루)엔 무풍(보라색)으로
                      // 오해하지 않도록 회색으로 "데이터 없음"을 표시한다.
                      Positioned.fromRect(
                        rect: fieldRect,
                        child: const ColoredBox(color: Color(0x993A3F46)),
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
                      size: mapSize,
                    ),
                    // 데이터 없는(회색) 시각엔 흐름선도 함께 숨긴다 — 안 그러면
                    // 이전 실데이터 시각의 흐름이 멈춘 채로 회색 위에 남아
                    // "데이터 없음"이라는 신호와 모순돼 보인다.
                    if (field.hasData)
                      Positioned.fromRect(
                        rect: fieldRect,
                        // 파티클만 매 프레임 다시 그려지도록 경계를 둔다.
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: WindMapPainter(
                              particles: widget.particles,
                              // 순백이 아니라 살짝 어두운 회청색으로 은은하게
                              // (Windy처럼 흰 선이 과하게 밝지 않게).
                              color: const Color(0xFFAEB9C6),
                              repaint: widget.repaint,
                            ),
                            size: fieldRect.size,
                          ),
                        ),
                      ),
                    // 지도 앱처럼 도시 이름만 확대 단계별로 표시(항구 점 라벨은
                    // 제거해 깔끔하게). 지역 선택은 우측 상단 지역 선택 버튼으로 한다.
                    MapCityLabelLayer(
                      projection: projection,
                      scale: _scale,
                      visibleBounds: visibleBounds,
                    ),
                    // 예보 표가 열려 있으면 그 지점에 윈디식 방향 나침반(로즈)을,
                    // 아니면 탭한 지점에 "상세 예보" 말풍선을 띄운다.
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
                    else if (widget.cursorLat case final plat?)
                      if (widget.cursorLon case final plon?)
                        Positioned(
                          left: projection.x(plon),
                          top: projection.y(plat),
                          // 커서 핀. 확대해도 크기가 일정하도록 반대로 축소하고
                          // 핀 끝(바닥 중앙)이 좌표에 오게 한다.
                          child: FractionalTranslation(
                            translation: const Offset(-0.5, -1),
                            child: Transform.scale(
                              scale: 1 / _scale,
                              alignment: Alignment.bottomCenter,
                              // 예전엔 테마 primary(스킨에 따라 어두운 남색·
                              // 회색 등)를 써서 지도 색 위에서 잘 안 보였다.
                              // 스킨과 무관하게 항상 잘 보이도록 흰색+진한
                              // 이중 그림자로 고정한다.
                              child: const Icon(
                                Icons.location_on,
                                size: 36,
                                color: Colors.white,
                                shadows: [
                                  Shadow(color: Colors.black, blurRadius: 6),
                                  Shadow(color: Colors.black87, blurRadius: 2),
                                ],
                              ),
                            ),
                          ),
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

/// 상세 예보 진입 전, 지도 상단에 뜨는 커서 지점 요약 바: 바람 세기·방향
/// 아이콘 + "상세 예보" 진입 버튼.
class _CursorWindBar extends StatelessWidget {
  const _CursorWindBar({
    required this.speed,
    required this.dir,
    required this.onDetail,
    required this.onClose,
  });

  final double speed;
  final double dir;
  final VoidCallback onDetail;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Colors.black, blurRadius: 4)];
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
        child: Row(
          children: [
            WindArrow(directionDeg: dir, size: 24, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              '${compassKo(dir)}\ud48d  ${formatWind(speed)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                shadows: shadow,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onDetail,
              icon: const Icon(Icons.insights, size: 18, color: Colors.white),
              label: const Text(
                '\uc0c1\uc138 \uc608\ubcf4',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  shadows: shadow,
                ),
              ),
            ),
            IconButton(
              onPressed: onClose,
              tooltip: '\ub2eb\uae30',
              icon: const Icon(
                Icons.close,
                color: Colors.white,
                shadows: shadow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Windy(몰입형 지도) 탭 오른쪽에 뜨는 아이콘 전용 세로 내비게이션.
/// 박스·라벨 없이 아이콘만. 현재 탭(Windy=air)은 강조색, 나머지는 흰색+그림자.
class _WindyNavRail extends StatelessWidget {
  const _WindyNavRail({required this.onSelect});

  final ValueChanged<int> onSelect;

  static const _icons = <(IconData, IconData)>[
    (Icons.home_outlined, Icons.home),
    (Icons.wb_sunny_outlined, Icons.wb_sunny),
    (Icons.waves_outlined, Icons.waves),
    (Icons.air_outlined, Icons.air),
    (Icons.settings_outlined, Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    const shadow = [Shadow(color: Colors.black, blurRadius: 5)];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _icons.length; i++)
          IconButton(
            onPressed: () => onSelect(i),
            iconSize: 26,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              i == windyTabIndex ? _icons[i].$2 : _icons[i].$1,
              color: i == windyTabIndex ? primary : Colors.white,
              shadows: shadow,
            ),
          ),
      ],
    );
  }
}

/// 지도 모드 하단에 붙는 윈디식 시간·날짜 스크러버. 슬라이더를 움직이면
/// 지도 바람장 시각([offset])이 바뀌어 히트맵·흐름선이 그 시각의 바람으로
/// 갱신된다. 현재 시각(now)에 "지금" 배지를 붙이고, ◀▶로 1시간씩 미세
/// 조정하며, "지금" 버튼으로 현재 시각으로 되돌린다.
class _MapTimeBar extends StatelessWidget {
  const _MapTimeBar({
    required this.series,
    required this.offset,
    required this.nowOffset,
    required this.synthetic,
    required this.onChanged,
    required this.onNow,
  });

  final WindFieldSeries series;
  final int offset;
  final int nowOffset;

  /// 실데이터 호출 실패로 합성(목업) 바람이 표시 중인지. 사용자에게 명확히
  /// 알려 실데이터(윈디)와 비교하다 혼동하지 않게 한다.
  final bool synthetic;
  final ValueChanged<int> onChanged;
  final VoidCallback onNow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxIdx = series.length - 1;
    final i = offset.clamp(0, maxIdx);
    final t = series.at(i).time;
    final isNow = i == nowOffset;
    // 현재 시각 대비 상대 표시(+N시간 / -N시간). 스텝 간격이 1시간이 아닐 수
    // 있으므로(서버 데이터는 3시간 간격) 인덱스 차가 아니라 실제 시각 차로
    // 계산해 정확히 표시한다.
    final diffH = t.difference(series.at(nowOffset).time).inHours;
    final rel = diffH == 0 ? '지금' : (diffH > 0 ? '+$diffH시간' : '$diffH시간');
    const shadow = [Shadow(color: Colors.black, blurRadius: 4)];
    // 흰 박스 대신 아래로 갈수록 살짝 어두워지는 투명 스크림(윈디식)만 깔아
    // 밝은 지도 위에서도 슬라이더·글씨가 읽히게 한다.
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0x80000000)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 이 시각이 모델의 실제 예보 범위 밖(지도가 회색)이면 이유를
              // 알려준다. synthetic(전체 폴백)과는 별개 상황이라 둘 다 뜰 수
              // 있다.
              if (!synthetic && !series.at(i).hasData)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.block,
                        size: 14,
                        color: Color(0xFFCBD3DB),
                        shadows: shadow,
                      ),
                      const SizedBox(width: 5),
                      const Expanded(
                        child: Text(
                          '이 시각은 아직 예보 범위 밖이라 데이터가 없습니다',
                          style: TextStyle(
                            color: Color(0xFFCBD3DB),
                            fontSize: 11,
                            shadows: shadow,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              // 실데이터를 못 받아 합성 바람이 표시 중이면 명확히 알린다.
              if (synthetic)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.wifi_off,
                        size: 14,
                        color: Color(0xFFFFB4A9),
                        shadows: shadow,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '실데이터 연결 실패 — 합성 바람 표시 중 (탭을 다시 열면 재시도)',
                          style: const TextStyle(
                            color: Color(0xFFFFB4A9),
                            fontSize: 11,
                            shadows: shadow,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  const Icon(
                    Icons.schedule,
                    size: 18,
                    color: Colors.white,
                    shadows: shadow,
                  ),
                  const SizedBox(width: 6),
                  if (isNow)
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
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${t.month}/${t.day} (${weekdayKo(t)}) ${formatHm(t)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          shadows: shadow,
                        ),
                      ),
                    ),
                  ),
                  if (!isNow) ...[
                    const SizedBox(width: 6),
                    Text(
                      rel,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        shadows: shadow,
                      ),
                    ),
                  ],
                  const Spacer(),
                  TextButton(
                    onPressed: isNow ? null : onNow,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Text('지금', style: TextStyle(shadows: shadow)),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    color: Colors.white,
                    icon: const Icon(Icons.chevron_left, shadows: shadow),
                    tooltip: '이전 시각',
                    onPressed: i > 0 ? () => onChanged(i - 1) : null,
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white38,
                        thumbColor: Colors.white,
                        overlayColor: Colors.white24,
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                      ),
                      child: Slider(
                        value: i.toDouble(),
                        min: 0,
                        max: maxIdx.toDouble(),
                        onChanged: (v) => onChanged(v.round()),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    color: Colors.white,
                    icon: const Icon(Icons.chevron_right, shadows: shadow),
                    tooltip: '다음 시각',
                    onPressed: i < maxIdx ? () => onChanged(i + 1) : null,
                  ),
                ],
              ),
            ],
          ),
        ),
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

  static const double _len = 84; // 막대 길이(중심→끝)
  static const double _thick = 16; // 막대 두께(글자가 들어갈 만큼만)
  static const double _d = 220; // 로즈 박스 한 변
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

  /// 방향 막대. **윈디식 관례**로 그린다: 바람/너울이 **불어오는 쪽(source)**에
  /// 막대를 두고, 뾰족한 화살촉이 **가운데 점(dot)을 향하게** 한다. 예를 들어
  /// 남풍(남쪽에서 붐)은 막대가 점 아래(남쪽)에 놓이고 화살촉이 위(점)로
  /// 간다. [dirDeg]는 기상 관례의 불어오는 방향이다.
  /// 글자는 막대가 어느 방향이든 뒤집히지 않도록 필요하면 180° 돌려 항상
  /// 바로 읽히게 한다.
  Widget _bar(double dirDeg, Color color, String label, String value) {
    final rad = (dirDeg + 180) * math.pi / 180;
    final u = Offset(math.sin(rad), -math.cos(rad)); // 화면상 진행(가는) 방향
    // 막대는 불어오는 쪽(-u, source)에 둔다. 화살촉은 그대로 진행 방향(+u)을
    // 가리키므로, 결과적으로 화살촉이 가운데 점을 향한다(윈디와 동일).
    final mid = _c - u * (_len / 2);
    var angle = math.atan2(u.dy, u.dx); // 캡슐 장축의 화면 각도
    // 글씨가 위를 향하도록: 왼쪽(cos<0)으로 향하면 같은 직선 위에서 180° 회전.
    var flip = false;
    if (math.cos(angle) < 0) {
      angle += math.pi;
      flip = true;
    }
    // 화살표 방향: 뒤집히지 않으면 막대의 바깥쪽(진행 방향)이 오른쪽, 뒤집히면
    // 왼쪽이다. 뾰족한 끝(tip)이 항상 바깥(진행 방향)을 향하도록 화살표 모양을
    // 좌우로 맞춘다.
    final pointRight = !flip;
    return Positioned(
      left: mid.dx,
      top: mid.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(
          angle: angle,
          child: ClipPath(
            clipper: _ArrowBarClipper(pointRight: pointRight),
            child: Container(
              width: _len,
              height: _thick,
              alignment: Alignment.center,
              // 뾰족한 끝·홈이 글자를 가리지 않게 좌우 여백을 준다.
              padding: const EdgeInsets.symmetric(horizontal: 11),
              color: color,
              // 뒤집힌 경우 라벨이 바깥쪽(tip)에 오도록 순서를 뒤집는다.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  textDirection: flip ? TextDirection.rtl : TextDirection.ltr,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 방향 막대의 화살표 모양: 한쪽 끝은 뾰족(tip), 반대쪽 끝은 화살 오늬처럼
/// 안으로 파인 홈(notch). [pointRight]로 뾰족한 끝의 좌우를 정한다.
class _ArrowBarClipper extends CustomClipper<Path> {
  _ArrowBarClipper({required this.pointRight});

  final bool pointRight;
  static const double _tip = 9;
  static const double _notch = 6;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final p = Path();
    if (pointRight) {
      p
        ..moveTo(0, 0)
        ..lineTo(w - _tip, 0)
        ..lineTo(w, h / 2) // 뾰족한 끝(오른쪽)
        ..lineTo(w - _tip, h)
        ..lineTo(0, h)
        ..lineTo(_notch, h / 2) // 오늬 홈(왼쪽)
        ..close();
    } else {
      p
        ..moveTo(w, 0)
        ..lineTo(_tip, 0)
        ..lineTo(0, h / 2) // 뾰족한 끝(왼쪽)
        ..lineTo(_tip, h)
        ..lineTo(w, h)
        ..lineTo(w - _notch, h / 2) // 오늬 홈(오른쪽)
        ..close();
    }
    return p;
  }

  @override
  bool shouldReclip(_ArrowBarClipper old) => old.pointRight != pointRight;
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

/// 파고/너울 높이(m) 표시 문자열. 양수인데 소수1자리로 반올림하면 0.0이
/// 되는 아주 작은 값(예: 0.03m)은 0.1로 올려 보여준다 — 0은 데이터 오류처럼
/// 보인다는 피드백 반영. 실제 0(성분 없음)만 0.0으로 둔다.
String _fmtWaveHeightM(double m) {
  if (m <= 0) return '0.0';
  final s = m.toStringAsFixed(1);
  return s == '0.0' ? '0.1' : s;
}

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

  /// 지점을 바꿔 다시 로딩하는 동안에도 표를 그대로 유지하기 위해 직전
  /// 예보를 붙잡아 둔다. 로딩 스피너로 표를 잠깐 없애면 스크롤 컨트롤러가
  /// 0으로 리셋되면서 보고 있던 날짜 위치가 처음으로 튕겨나가는 문제를 막는다.
  MarineForecast? _lastForecast;

  /// [steps] 중 현재 시각(서울 기준)과 가장 가까운 칸의 인덱스.
  int _closestToNow(List<HourlyMarine> steps) {
    final now = nowKst();
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
  static const double _labelW = 68;
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
    // 흰 박스 대신 어두운 반투명 스크림(윈디식)에 흰 글씨로. 표 안의 기본
    // 글씨색이 지도 위에서 안 보이지 않도록 이 패널만 흰색 텍스트 테마로 감싼다
    // (색칠된 셀 글씨는 셀별로 대비색을 계산하므로 그대로 잘 보인다).
    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(
          context,
        ).textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      child: Container(
        decoration: const BoxDecoration(
          // 표를 더 투명하게(기존의 절반 수준). 아래로 갈수록 살짝만 어둡게.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x590B1622), Color(0x800B1622)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                    const Icon(
                      Icons.location_on,
                      size: 18,
                      color: Color(0xFF8FD3FF),
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      // 밝은 지도 위에서도 보이도록 밝은(너무 희지 않은) 회백색
                      // + 그림자로. 검정 위 검정으로 안 보이던 문제 해결.
                      child: Text(
                        '상세 예보  ·  ${widget.location.name}',
                        style: const TextStyle(
                          color: Color(0xFFDCE3EA),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                      tooltip: '지도로 돌아가기',
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (context) {
                  // 지점 변경 재로딩 중에도 직전 예보를 유지해 표가 사라지지
                  // 않게 한다(표를 스피너로 바꾸면 스크롤이 0으로 리셋된다).
                  final forecast = forecastAsync.valueOrNull ?? _lastForecast;
                  if (forecastAsync.hasValue) {
                    _lastForecast = forecastAsync.value;
                  }
                  if (forecast == null) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: forecastAsync.hasError
                          ? const Text('예보를 불러오지 못했습니다')
                          : const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                    );
                  }
                  // 3시간 간격으로 향후 최대 16일(Open-Meteo 예보 상한)을 뽑는다.
                  // 마린/바람 API가 실제로 주는 만큼 그대로 보여준다(지도의
                  // 바람장 horizon에 맞춰 자르지 않음 — 최신·최장 실데이터를
                  // 우선한다). 지도 쪽은 데이터가 없는 미래 날짜를 회색으로
                  // 표시해 상세 표와 별도로 처리한다.
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
                            const Icon(
                              Icons.schedule,
                              size: 18,
                              color: Color(0xFF8FD3FF),
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 4),
                              ],
                            ),
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
                        hasWaveData: forecast.hasWaveData,
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
    required this.hasWaveData,
    required this.onColumnTap,
  });

  final List<HourlyMarine> steps;
  final int selected;
  final int nowIndex;
  final ScrollController controller;

  /// false면 육지 지점이라 파도·너울·너울주기·파력 행을 표에서 뺀다.
  final bool hasWaveData;
  final ValueChanged<int> onColumnTap;

  @override
  Widget build(BuildContext context) {
    final rows = [
      '시간',
      '날씨',
      '기온 °C',
      '바람 m/s',
      '돌풍 m/s',
      if (hasWaveData) ...['파도 m', '너울1 m', '너울주기 s', '파력 kW/m', '수온 °C'],
    ];
    // 단위(m/s 등)까지 잘리지 않도록 라벨 글씨를 조금 작게 한다.
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontSize: 10.5);
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
                      padding: const EdgeInsets.only(right: 6),
                      child: Align(
                        alignment: Alignment.centerRight,
                        // 혹시 더 긴 라벨이 와도 잘리지 않게 오른쪽 정렬로 축소.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            rows[r],
                            maxLines: 1,
                            textAlign: TextAlign.right,
                            style: labelStyle,
                          ),
                        ),
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
                  hasWaveData: hasWaveData,
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
    required this.hasWaveData,
    required this.onTap,
  });

  final HourlyMarine hour;
  final bool isNewDay;
  final bool isSelected;
  final bool isNow;

  /// false면 육지 지점이라 파도·너울·너울주기·파력 칸을 뺀다(라벨 열과 동일).
  final bool hasWaveData;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final windC = windSpeedColor(hour.windSpeedMs);
    final gustC = windSpeedColor(hour.windGustMs);
    final waveC = waveHeightColor(hour.waveHeightM);
    final swellC = waveHeightColor(hour.swellHeightM);
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
                                    color: const Color(0xFF8FD3FF),
                                    fontWeight: FontWeight.bold,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black,
                                        blurRadius: 3,
                                      ),
                                    ],
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
            // 육지 지점이면 파도·너울·너울주기·파력·수온을 아예 뺀다(라벨 열과 동일).
            if (hasWaveData) ...[
              // 파도(유의파고=총 파고). Windy가 대표로 보여주는 값이라 함께
              // 표시해 비교가 맞게 한다(너울1은 그 성분 분해).
              arrowCell(
                _fmtWaveHeightM(hour.waveHeightM),
                hour.waveDirectionDeg,
                bg: waveC.withValues(alpha: 0.9),
              ),
              arrowCell(
                _fmtWaveHeightM(hour.swellHeightM),
                hour.swellDirectionDeg,
                bg: swellC.withValues(alpha: 0.85),
              ),
              // 너울 주기(s). 성분(너울)의 주기라 방향 화살표 없이 숫자만.
              cell(
                hour.swellPeriodS > 0
                    ? hour.swellPeriodS.toStringAsFixed(1)
                    : '-',
              ),
              cell(formatWavePower(hour.wavePowerKw)),
              cell('${hour.waterTempC.round()}'),
            ],
          ],
        ),
      ),
    );
  }
}
