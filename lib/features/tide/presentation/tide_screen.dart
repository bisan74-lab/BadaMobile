import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/mul_ttae.dart';
import '../../locations/presentation/providers.dart';
import 'providers.dart';
import 'widgets/tide_chart.dart';

/// 조석·물때 화면 (바다타임 영역).
class TideScreen extends ConsumerStatefulWidget {
  const TideScreen({super.key});

  @override
  ConsumerState<TideScreen> createState() => _TideScreenState();
}

class _TideScreenState extends ConsumerState<TideScreen> {
  DateTime _date = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(selectedLocationProvider);
    final tideAsync = ref.watch(
      tideDayProvider((location: location, date: _date)),
    );
    final mulTtae = mulTtaeFor(_date);
    final isToday = DateUtils.isSameDay(_date, DateTime.now());

    return Scaffold(
      appBar: AppBar(title: Text('물때 · ${location.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(
                  () => _date = _date.subtract(const Duration(days: 1)),
                ),
              ),
              Column(
                children: [
                  Text(
                    formatMonthDay(_date),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  _MulTtaeBadge(mulTtae: mulTtae),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () =>
                    setState(() => _date = _date.add(const Duration(days: 1))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          tideAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('조석 정보를 불러오지 못했습니다: $e'),
            ),
            data: (tide) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                    child: TideChart(
                      hourlyHeightsCm: tide.hourlyHeightsCm,
                      now: isToday ? DateTime.now() : null,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...tide.extremes.map(
                  (e) => Card(
                    child: ListTile(
                      leading: Icon(
                        e.isHigh ? Icons.arrow_upward : Icons.arrow_downward,
                        color: e.isHigh ? Colors.redAccent : Colors.blueAccent,
                      ),
                      title: Text(e.isHigh ? '만조' : '간조'),
                      trailing: Text(
                        '${formatHm(e.time)}  ·  ${formatTideHeight(e.heightCm)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
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

class _MulTtaeBadge extends StatelessWidget {
  const _MulTtaeBadge({required this.mulTtae});

  final MulTtae mulTtae;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = mulTtae.isSari
        ? (scheme.errorContainer, scheme.onErrorContainer)
        : mulTtae.isJogeum
        ? (scheme.surfaceContainerHighest, scheme.onSurfaceVariant)
        : (scheme.primaryContainer, scheme.onPrimaryContainer);
    final suffix = mulTtae.isSari
        ? ' · 사리'
        : mulTtae.isJogeum
        ? ' · 소조기'
        : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '${mulTtae.label}$suffix (음력 ${mulTtae.lunarDay}일)',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
      ),
    );
  }
}
