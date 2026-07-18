import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_gate_config.dart';
import 'app_gate_repository.dart';

final appGateRepositoryProvider = Provider<AppGateRepository>(
  (ref) => AppGateRepository(),
);

/// 앱 시작 시 한 번 확인하는 강제 업데이트 게이트 상태.
final appGateProvider = FutureProvider<AppGateConfig>((ref) {
  return ref.watch(appGateRepositoryProvider).fetch();
});
