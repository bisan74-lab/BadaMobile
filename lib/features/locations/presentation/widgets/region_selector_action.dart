import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'location_picker_sheet.dart';

/// 모든 탭의 AppBar 우측에 공통으로 붙는 지역 선택 버튼.
/// 현재 선택된 지역 이름을 아이콘 왼쪽에 보여주고, 탭하면 지역 선택
/// 바텀시트가 열린다. [forWeather]가 true면 날씨 탭 전용 지역
/// ([weatherLocationProvider])를 대상으로 하며, 다른 탭과 분리된다.
class RegionSelectorAction extends ConsumerWidget {
  const RegionSelectorAction({super.key, this.forWeather = false});

  final bool forWeather;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(
      forWeather ? weatherLocationProvider : selectedLocationProvider,
    );
    // 앱바가 위젯 단에서 foregroundColor를 바꾸는 화면(물때&날씨의 투명
    // 앱바=흰색)도 있으므로, 테마 값이 아니라 **현재 앱바가 실제로 적용한
    // 전경색**(IconTheme)을 따른다 — 어두운 배경엔 밝은 글자, 밝은 배경엔
    // 어두운 글자가 자동으로 된다(사용자 지적).
    final fg =
        IconTheme.of(context).color ??
        Theme.of(context).appBarTheme.foregroundColor;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton.icon(
        onPressed: () =>
            showLocationPickerSheet(context, forWeather: forWeather),
        icon: const Icon(Icons.edit_location_alt_outlined),
        iconAlignment: IconAlignment.end,
        label: Text(location.name, style: TextStyle(color: fg)),
        style: TextButton.styleFrom(foregroundColor: fg),
      ),
    );
  }
}
