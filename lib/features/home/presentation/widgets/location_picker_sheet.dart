import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../locations/presentation/providers.dart';

/// 홈 화면 상단 우측 버튼으로 여는 지역 선택 바텀시트.
/// 지역 탭의 전체 화면 목록을 대신할 만큼 가벼운 검색+목록만 제공한다.
Future<void> showLocationPickerSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _LocationPickerSheet(),
  );
}

class _LocationPickerSheet extends ConsumerStatefulWidget {
  const _LocationPickerSheet();

  @override
  ConsumerState<_LocationPickerSheet> createState() =>
      _LocationPickerSheetState();
}

class _LocationPickerSheetState extends ConsumerState<_LocationPickerSheet> {
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

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
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
                final isSelected = loc.id == selected.id;
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
                  onTap: () {
                    ref.read(selectedLocationProvider.notifier).select(loc);
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
