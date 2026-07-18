import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../locations/data/models/sea_location.dart';
import '../../locations/presentation/providers.dart';
import '../../locations/presentation/widgets/region_selector_action.dart';
import '../data/models/land_weather.dart';
import '../data/weather_code.dart';
import 'providers.dart';
import 'widgets/weather_icon.dart';

/// 날씨 예보 화면. 기상청(근일) + Open-Meteo(15일·부가정보)로 만든 지역 육상
/// 날씨를 24시간·15일 예보와 상세 정보(바람·습도·자외선·가시거리·일출몰·공기질·
/// 2시간 강수)로 보여준다.
class KmaWeatherScreen extends ConsumerStatefulWidget {
  const KmaWeatherScreen({super.key});

  @override
  ConsumerState<KmaWeatherScreen> createState() => _KmaWeatherScreenState();
}

class _KmaWeatherScreenState extends ConsumerState<KmaWeatherScreen> {
  bool _show15 = false;

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(selectedLocationProvider);
    final forecastAsync = ref.watch(weatherForecastProvider(location));

    return Scaffold(
      appBar: AppBar(
        title: const Text('날씨 예보'),
        actions: const [RegionSelectorAction()],
      ),
      body: forecastAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('날씨 예보를 불러오지 못했습니다: $e')),
        data: (f) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _CurrentHeader(location: location, now: f.now),
            const SizedBox(height: 12),
            _TodayTomorrow(daily: f.daily),
            if (f.nowcast.any((n) => n.precipMm > 0)) ...[
              const SizedBox(height: 12),
              _NowcastCard(steps: f.nowcast),
            ],
            const SizedBox(height: 16),
            Text('24시간 예보', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _HourlyStrip(hours: f.next24h),
            const SizedBox(height: 16),
            _DailyHeader(
              show15: _show15,
              onChanged: (v) => setState(() => _show15 = v),
            ),
            const SizedBox(height: 4),
            for (final d in f.daily.take(_show15 ? 15 : 7)) _DailyRow(day: d),
            const SizedBox(height: 16),
            Text('상세 정보', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _DetailGrid(forecast: f),
          ],
        ),
      ),
    );
  }
}

class _CurrentHeader extends StatelessWidget {
  const _CurrentHeader({required this.location, required this.now});

  final SeaLocation location;
  final WeatherNow now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.primaryContainer],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  location.name,
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${now.tempC.round()}°',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 44,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${wmoLabelKo(now.weatherCode)}  ·  체감 ${now.feelsLikeC.round()}°',
                  style: TextStyle(
                    color: scheme.onPrimary.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          WeatherIcon(code: now.weatherCode, size: 72),
        ],
      ),
    );
  }
}

class _TodayTomorrow extends StatelessWidget {
  const _TodayTomorrow({required this.daily});

  final List<WeatherDay> daily;

  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) return const SizedBox.shrink();
    final today = daily.first;
    final tmw = daily.length > 1 ? daily[1] : null;
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(label: '오늘', day: today),
        ),
        const SizedBox(width: 12),
        if (tmw != null)
          Expanded(
            child: _SummaryCard(label: '내일', day: tmw),
          ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.day});

  final String label;
  final WeatherDay day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(
                  wmoLabelKo(day.weatherCode),
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${day.tempMaxC.round()}° / ${day.tempMinC.round()}°',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          WeatherIcon(code: day.weatherCode, size: 40),
        ],
      ),
    );
  }
}

/// 2시간 이내 강수 예보(비/진눈깨비/눈/우박/가랑비) — 15분 간격 나우캐스트.
class _NowcastCard extends StatelessWidget {
  const _NowcastCard({required this.steps});

  final List<NowcastStep> steps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final firstWet = steps.firstWhere(
      (s) => s.precipMm > 0,
      orElse: () => steps.first,
    );
    final kind = precipKindKo(firstWet.weatherCode) ?? '강수';
    final mins = firstWet.time
        .difference(DateTime.now())
        .inMinutes
        .clamp(0, 120);
    final maxMm = steps.fold<double>(
      0,
      (m, s) => s.precipMm > m ? s.precipMm : m,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.umbrella, size: 18, color: scheme.onTertiaryContainer),
              const SizedBox(width: 6),
              Text(
                mins <= 0 ? '지금 $kind' : '약 $mins분 후 $kind',
                style: TextStyle(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 30,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final s in steps)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      height: maxMm == 0 ? 2 : (4 + 26 * (s.precipMm / maxMm)),
                      decoration: BoxDecoration(
                        color: s.precipMm > 0
                            ? scheme.primary
                            : scheme.onTertiaryContainer.withValues(
                                alpha: 0.15,
                              ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '지금 ~ 2시간 (15분 간격)',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onTertiaryContainer),
          ),
        ],
      ),
    );
  }
}

class _HourlyStrip extends StatelessWidget {
  const _HourlyStrip({required this.hours});

  final List<WeatherHour> hours;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: hours.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final h = hours[i];
          final night = h.time.hour < 6 || h.time.hour >= 19;
          return Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${h.precipProbPct}%',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                WeatherIcon(code: h.weatherCode, size: 30, night: night),
                Text(
                  i == 0 ? '지금' : formatHm(h.time),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  '${h.tempC.round()}°',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DailyHeader extends StatelessWidget {
  const _DailyHeader({required this.show15, required this.onChanged});

  final bool show15;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          show15 ? '15일 예보' : '7일 예보',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SegmentedButton<bool>(
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: const [
            ButtonSegment(value: false, label: Text('7일')),
            ButtonSegment(value: true, label: Text('15일')),
          ],
          selected: {show15},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ],
    );
  }
}

class _DailyRow extends StatelessWidget {
  const _DailyRow({required this.day});

  final WeatherDay day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = DateUtils.isSameDay(day.date, DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isToday ? '오늘' : '${weekdayKo(day.date)}요일',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${day.date.month}/${day.date.day}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          WeatherIcon(code: day.weatherCode, size: 34),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              wmoLabelKo(day.weatherCode),
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.umbrella, size: 14, color: scheme.primary),
          const SizedBox(width: 2),
          SizedBox(
            width: 40,
            child: Text(
              '${day.precipProbMaxPct}%',
              style: TextStyle(color: scheme.primary, fontSize: 12),
            ),
          ),
          SizedBox(
            width: 74,
            child: Text(
              '${day.tempMaxC.round()}° / ${day.tempMinC.round()}°',
              textAlign: TextAlign.right,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.forecast});

  final WeatherForecast forecast;

  @override
  Widget build(BuildContext context) {
    final now = forecast.now;
    final today = forecast.daily.isNotEmpty ? forecast.daily.first : null;
    final air = forecast.air;
    final tiles = <Widget>[
      _DetailTile(
        icon: Icons.air,
        label: '바람 · 돌풍',
        value: '${compassKo(now.windDirDeg)} ${formatWind(now.windSpeedMs)}',
        sub: '돌풍 ${formatWind(now.windGustMs)}',
      ),
      _DetailTile(
        icon: Icons.water_drop_outlined,
        label: '습도',
        value: '${now.humidityPct}%',
      ),
      _DetailTile(
        icon: Icons.wb_sunny_outlined,
        label: '자외선 지수',
        value: _uvLabel(now.uvIndex),
      ),
      _DetailTile(
        icon: Icons.visibility_outlined,
        label: '가시거리',
        value: '${now.visibilityKm.round()}km',
      ),
      if (today?.sunrise != null && today?.sunset != null)
        _DetailTile(
          icon: Icons.wb_twilight,
          label: '일출 · 일몰',
          value: formatHm(today!.sunrise!),
          sub: '일몰 ${formatHm(today.sunset!)}',
        ),
      if (air != null)
        _DetailTile(
          icon: Icons.masks_outlined,
          label: '공기질 (PM2.5)',
          value: '${air.gradeKo} ${air.pm2_5.round()}',
          sub: 'PM10 ${air.pm10.round()}',
        ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.4,
      children: tiles,
    );
  }

  String _uvLabel(double uv) {
    final level = uv <= 2
        ? '낮음'
        : uv <= 5
        ? '보통'
        : uv <= 7
        ? '높음'
        : uv <= 10
        ? '매우높음'
        : '위험';
    return '${uv.round()} $level';
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                if (sub != null)
                  Text(
                    sub!,
                    style: Theme.of(context).textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
