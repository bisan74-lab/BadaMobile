import 'package:bada_mobile/core/storage/cache_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('저장한 JSON을 그대로 읽어온다', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = CacheStore(prefs);

    await cache.writeJson('k', {'a': 1, 'b': 'x'});
    expect(cache.readJson('k'), {'a': 1, 'b': 'x'});
  });

  test('없는 키는 null을 돌려준다', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = CacheStore(prefs);
    expect(cache.readJson('nope'), isNull);
  });

  test('손상된(비-JSON) 값은 null로 취급한다', () async {
    SharedPreferences.setMockInitialValues({'cache_v1_bad': 'not-json{'});
    final prefs = await SharedPreferences.getInstance();
    final cache = CacheStore(prefs);
    expect(cache.readJson('bad'), isNull);
  });
}
