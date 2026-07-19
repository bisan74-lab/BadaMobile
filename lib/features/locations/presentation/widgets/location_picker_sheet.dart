import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/sea_location.dart';
import '../providers.dart';

/// 각 탭 상단 우측 버튼([RegionSelectorAction])으로 여는 지역 선택
/// 바텀시트. 현재 위치 · 지명 검색(읍/면/동 단위) · 즐겨찾기 · 선택을
/// 가벼운 시트 하나로 제공한다.
Future<void> showLocationPickerSheet(
  BuildContext context, {
  bool forWeather = false,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _LocationPickerSheet(forWeather: forWeather),
  );
}

class _LocationPickerSheet extends ConsumerStatefulWidget {
  const _LocationPickerSheet({required this.forWeather});

  /// true면 날씨 탭 전용 지역([weatherLocationProvider])에만 반영한다.
  final bool forWeather;

  @override
  ConsumerState<_LocationPickerSheet> createState() =>
      _LocationPickerSheetState();
}

class _LocationPickerSheetState extends ConsumerState<_LocationPickerSheet> {
  String _query = '';

  /// 디바운스된 검색어(지오코딩 API 호출용).
  String _geoQuery = '';
  Timer? _debounce;
  bool _locating = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    setState(() => _query = v.trim());
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _geoQuery = _query);
    });
  }

  void _choose(SeaLocation loc) {
    if (widget.forWeather) {
      ref.read(weatherLocationProvider.notifier).select(loc);
    } else {
      ref.read(selectedLocationProvider.notifier).select(loc);
    }
    Navigator.of(context).pop();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      final loc = await resolveCurrentLocation();
      if (!mounted) return;
      _choose(loc);
    } catch (e) {
      if (!mounted) return;
      setState(() => _locating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(locationsProvider);
    final selected = ref.watch(
      widget.forWeather ? weatherLocationProvider : selectedLocationProvider,
    );
    final favorites = ref.watch(favoritesProvider);
    final scheme = Theme.of(context).colorScheme;

    final filtered =
        all
            .where(
              (l) =>
                  _query.isEmpty ||
                  l.name.contains(_query) ||
                  l.region.contains(_query),
            )
            .toList()
          ..sort((a, b) {
            final favDiff =
                (favorites.contains(b.id) ? 1 : 0) -
                (favorites.contains(a.id) ? 1 : 0);
            return favDiff != 0 ? favDiff : a.name.compareTo(b.name);
          });

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('지역 선택', style: Theme.of(context).textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '동·읍·면·시 검색 (예: 마곡동, 오산 원동, 목포)',
                border: OutlineInputBorder(),
              ),
              onChanged: _onQueryChanged,
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                // 현재 위치 — 날씨 탭에서만 제공(홈/물때/Windy는 미적용).
                if (widget.forWeather) ...[
                  ListTile(
                    leading: _locating
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.my_location, color: scheme.primary),
                    title: const Text('현재 위치로 설정'),
                    subtitle: const Text('GPS로 지금 있는 곳의 날씨를 본다'),
                    onTap: _locating ? null : _useCurrentLocation,
                  ),
                  const Divider(height: 1),
                ],

                // 내장 지점(즐겨찾기·주요 항구/지역).
                for (final loc in filtered)
                  ListTile(
                    leading: Icon(
                      loc.id == selected.id
                          ? Icons.check_circle
                          : Icons.place_outlined,
                      color: loc.id == selected.id ? scheme.primary : null,
                    ),
                    title: Text(loc.name),
                    subtitle: Text(loc.region),
                    trailing: IconButton(
                      icon: Icon(
                        favorites.contains(loc.id)
                            ? Icons.star
                            : Icons.star_border,
                        color: favorites.contains(loc.id) ? Colors.amber : null,
                      ),
                      onPressed: () =>
                          ref.read(favoritesProvider.notifier).toggle(loc.id),
                    ),
                    onTap: () => _choose(loc),
                  ),

                // 지명 검색 결과(읍/면/동 등 세분화 — Open-Meteo Geocoding).
                if (_geoQuery.length >= 2)
                  _GeoResults(query: _geoQuery, onPick: _choose),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 지오코딩 검색 결과 섹션.
class _GeoResults extends ConsumerWidget {
  const _GeoResults({required this.query, required this.onPick});

  final String query;
  final ValueChanged<SeaLocation> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(geocodingSearchProvider(query));
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '검색 결과',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text('검색 결과를 불러오지 못했습니다.'),
          ),
          data: (places) {
            if (places.isEmpty) {
              return const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text('일치하는 지명이 없습니다. 더 넓은 지명으로 검색해 보세요.'),
              );
            }
            return Column(
              children: [
                for (final p in places)
                  ListTile(
                    leading: const Icon(Icons.travel_explore),
                    title: Text(p.name),
                    subtitle: p.admin.isEmpty ? null : Text(p.admin),
                    onTap: () => onPick(p.toLocation()),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
