import 'package:bada_mobile/core/remote_config/app_gate_config.dart';
import 'package:bada_mobile/core/remote_config/app_gate_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AppGateConfig.fromJson', () {
    test('필드를 그대로 읽는다', () {
      final config = AppGateConfig.fromJson({
        'forceUpgrade': true,
        'message': '업데이트하세요',
        'storeUrl': 'https://play.google.com/store/apps/details?id=x',
      });
      expect(config.forceUpgrade, isTrue);
      expect(config.message, '업데이트하세요');
      expect(
        config.storeUrl,
        'https://play.google.com/store/apps/details?id=x',
      );
    });

    test('필드가 없으면 안전한 기본값을 쓴다', () {
      final config = AppGateConfig.fromJson({});
      expect(config.forceUpgrade, isFalse);
      expect(config.message, isNotEmpty);
      expect(config.storeUrl, '');
    });
  });

  group('AppGateRepository', () {
    test('정상 응답이면 forceUpgrade 값을 그대로 반환한다', () async {
      final client = MockClient(
        (request) async => http.Response(
          '{"forceUpgrade": true, "message": "새 버전 필요", '
          '"storeUrl": "https://example.com"}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final repo = AppGateRepository(client: client);
      final config = await repo.fetch();
      expect(config.forceUpgrade, isTrue);
      expect(config.message, '새 버전 필요');
    });

    test('응답이 200이 아니면 항상 실행 허용(disabled)으로 처리한다', () async {
      final client = MockClient((request) async => http.Response('', 500));
      final repo = AppGateRepository(client: client);
      final config = await repo.fetch();
      expect(config.forceUpgrade, isFalse);
    });

    test('네트워크 실패 시에도 실행 허용(disabled)으로 처리한다', () async {
      final client = MockClient((request) async => throw Exception('오프라인'));
      final repo = AppGateRepository(client: client);
      final config = await repo.fetch();
      expect(config, same(AppGateConfig.disabled));
    });

    test('JSON이 아니거나 형식이 다르면 실행 허용(disabled)으로 처리한다', () async {
      final client = MockClient(
        (request) async => http.Response('["not", "a", "map"]', 200),
      );
      final repo = AppGateRepository(client: client);
      final config = await repo.fetch();
      expect(config.forceUpgrade, isFalse);
    });
  });
}
