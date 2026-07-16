import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../locations/data/models/sea_location.dart';
import '../../locations/data/sample_locations.dart';
import '../../locations/presentation/providers.dart';
import '../data/models/wind_field.dart';
import 'wind_field_providers.dart';
import 'widgets/wind_map_painter.dart';

/// 바람 지도 (윈디 스타일 파티클 흐름 시각화).
///
/// 격자별 바람 벡터장을 [WindField]로 받아, 파티클이 벡터를 따라
/// 흐르며 궤적을 남기는 애니메이션으로 그린다. 흐름의 빠르기는
/// 화면 안에서 알아보기 쉽도록 과장한 값이며 실제 이동 속도가 아니다.
class WindMapScreen extends ConsumerStatefulWidget {
  const WindMapScreen({super.key});

  @override
  ConsumerState<WindMapScreen> createState() => _WindMapScreenState();
}

class _WindMapScreenState extends ConsumerState<WindMapScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  final _random = math.Random();
  final List<WindParticle> _particles = [];
  WindField? _field;

  static const _particleCount = 240;
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

  void _ensureSeeded(WindField field) {
    if (_field != null) return;
    _field = field;
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
    final field = _field;
    if (field == null) return;
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
    final fieldAsync = ref.watch(windFieldProvider);
    final selected = ref.watch(selectedLocationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('바람 지도'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(windFieldProvider),
          ),
        ],
      ),
      body: fieldAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('바람장을 불러오지 못했습니다: $e')),
        data: (field) {
          _ensureSeeded(field);
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio:
                        (field.maxLon - field.minLon) /
                        (field.maxLat - field.minLat),
                    child: Container(
                      margin: const EdgeInsets.all(12),
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
                          return Stack(
                            children: [
                              CustomPaint(
                                painter: WindMapPainter(
                                  particles: _particles,
                                  color: Colors.cyanAccent,
                                ),
                                size: size,
                              ),
                              for (final loc in sampleLocations)
                                if (field.contains(loc.latitude, loc.longitude))
                                  _LocationMarker(
                                    location: loc,
                                    highlighted: loc.id == selected.id,
                                    left:
                                        (loc.longitude - field.minLon) /
                                            (field.maxLon - field.minLon) *
                                            size.width -
                                        4,
                                    top:
                                        (1 -
                                                (loc.latitude - field.minLat) /
                                                    (field.maxLat -
                                                        field.minLat)) *
                                            size.height -
                                        4,
                                  ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  '${field.time.hour.toString().padLeft(2, '0')}:'
                  '${field.time.minute.toString().padLeft(2, '0')} 기준 · '
                  '흐름선은 바람이 불어가는 방향을 나타내며, '
                  '보기 쉽도록 빠르기를 과장했습니다.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
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
    required this.left,
    required this.top,
  });

  final SeaLocation location;
  final bool highlighted;
  final double left;
  final double top;

  @override
  Widget build(BuildContext context) {
    final size = highlighted ? 10.0 : 6.0;
    return Positioned(
      left: left - (size - 8) / 2,
      top: top - (size - 8) / 2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: size,
            height: size,
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
                shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
