import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'location_picker_sheet.dart';

/// 모든 탭의 AppBar 우측에 공통으로 붙는 지역 선택 버튼.
/// 현재 선택된 지역 이름을 아이콘 왼쪽에 보여주고, 탭하면 지역 선택
/// 바텀시트가 열린다.
class RegionSelectorAction extends ConsumerWidget {
  const RegionSelectorAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(selectedLocationProvider);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton.icon(
        onPressed: () => showLocationPickerSheet(context),
        icon: const Icon(Icons.edit_location_alt_outlined),
        iconAlignment: IconAlignment.end,
        label: Text(
          location.name,
          style: TextStyle(
            color: Theme.of(context).appBarTheme.foregroundColor,
          ),
        ),
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        ),
      ),
    );
  }
}
