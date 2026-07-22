import 'package:bada_mobile/core/storage/prefs.dart';
import 'package:bada_mobile/features/locations/data/sample_locations.dart';
import 'package:bada_mobile/features/locations/presentation/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> makeContainer() async {
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('선택 지역이 저장되고 새 컨테이너(재시작)에서 복원된다', () async {
    SharedPreferences.setMockInitialValues({});
    final busan = sampleLocations.firstWhere((l) => l.id == 'busan');
    final muchangpo = sampleLocations.firstWhere((l) => l.id == 'muchangpo');

    final first = await makeContainer();
    // 저장된 선택이 없으면 기본 지역(무창포항)으로 시작한다.
    expect(first.read(selectedLocationProvider), muchangpo);
    first.read(selectedLocationProvider.notifier).select(busan);

    final second = await makeContainer(); // 앱 재시작에 해당
    expect(second.read(selectedLocationProvider), busan);
  });

  test('즐겨찾기가 저장되고 복원되며 토글로 해제된다', () async {
    SharedPreferences.setMockInitialValues({});

    final first = await makeContainer();
    first.read(favoritesProvider.notifier).toggle('mokpo');
    first.read(favoritesProvider.notifier).toggle('jeju');

    final second = await makeContainer();
    expect(second.read(favoritesProvider), {'mokpo', 'jeju'});

    second.read(favoritesProvider.notifier).toggle('jeju');
    final third = await makeContainer();
    expect(third.read(favoritesProvider), {'mokpo'});
  });

  test('저장된 지역 id가 목록에 없으면 기본 지역(무창포항)으로 복원된다', () async {
    SharedPreferences.setMockInitialValues({
      'selected_location_id': 'no_such_place',
    });
    final container = await makeContainer();
    final muchangpo = sampleLocations.firstWhere((l) => l.id == 'muchangpo');
    expect(container.read(selectedLocationProvider), muchangpo);
  });
}
