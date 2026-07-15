import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱 시작 시 main()에서 실제 인스턴스로 override 된다.
/// 테스트에서는 SharedPreferences.setMockInitialValues 후 주입한다.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('main()에서 override 필요'),
);
