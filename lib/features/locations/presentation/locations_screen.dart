import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// 지점 검색·선택·즐겨찾기 화면.
class LocationsScreen extends ConsumerStatefulWidget {
  const LocationsScreen({super.key});

  @override
  ConsumerState<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends ConsumerState<LocationsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(locationsProvider);
    final selected = ref.watch(selectedLocationProvider);
    final favorites = ref.watch(favoritesProvider);

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

    return Scaffold(
      appBar: AppBar(title: const Text('지역 선택')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '지점 이름 또는 해역 검색 (예: 목포, 서해)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final loc = filtered[i];
                final isSelected = loc == selected;
                final isFav = favorites.contains(loc.id);
                return ListTile(
                  leading: Icon(
                    isSelected ? Icons.check_circle : Icons.place_outlined,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(loc.name),
                  subtitle: Text(loc.region),
                  trailing: IconButton(
                    icon: Icon(
                      isFav ? Icons.star : Icons.star_border,
                      color: isFav ? Colors.amber : null,
                    ),
                    onPressed: () =>
                        ref.read(favoritesProvider.notifier).toggle(loc.id),
                  ),
                  onTap: () =>
                      ref.read(selectedLocationProvider.notifier).select(loc),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
