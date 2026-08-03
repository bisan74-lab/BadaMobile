import 'dart:convert';
import 'dart:io';

import 'package:bada_mobile/core/remote_config/app_gate_config.dart';
import 'package:bada_mobile/core/remote_config/app_gate_repository.dart';
import 'package:bada_mobile/features/settings/app_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AppGateConfig gate({bool force = false, String min = ''}) => AppGateConfig(
  forceUpgrade: force,
  minSupportedVersion: min,
  message: '',
  storeUrl: '',
);

void main() {
  group('AppGateConfig.fromJson', () {
    test('필드를 그대로 읽는다', () {
      final config = AppGateConfig.fromJson({
        'forceUpgrade': true,
        'minSupportedVersion': '1.2.3',
        'message': '업데이트하세요',
        'storeUrl': 'https://play.google.com/store/apps/details?id=x',
      });
      expect(config.forceUpgrade, isTrue);
      expect(config.minSupportedVersion, '1.2.3');
      expect(config.message, '업데이트하세요');
      expect(
        config.storeUrl,
        'https://play.google.com/store/apps/details?id=x',
      );
    });

    test('필드가 없으면 안전한 기본값을 쓴다', () {
      final config = AppGateConfig.fromJson({});
      expect(config.forceUpgrade, isFalse);
      expect(config.minSupportedVersion, '');
      expect(config.message, isNotEmpty);
      expect(config.storeUrl, '');
    });
  });

  group('AppGateConfig.blocks — 버전 기준 차단', () {
    test('최소 버전보다 낮으면 막고, 같거나 높으면 통과시킨다', () {
      final g = gate(min: '0.4.6');
      expect(g.blocks('0.4.5'), isTrue);
      expect(g.blocks('0.3.9'), isTrue);
      expect(g.blocks('0.4.6'), isFalse); // 같으면 통과
      expect(g.blocks('0.4.7'), isFalse);
      expect(g.blocks('1.0.0'), isFalse);
    });

    test('자릿수가 달라도 비교한다', () {
      expect(gate(min: '1.0').blocks('0.9.9'), isTrue);
      expect(gate(min: '1.0').blocks('1.0.0'), isFalse);
      expect(gate(min: '0.5').blocks('0.5.1'), isFalse);
      // 두 자리 숫자를 문자열로 비교하면 '10' < '9'가 되어 잘못 막힌다.
      expect(gate(min: '0.9.0').blocks('0.10.0'), isFalse);
    });

    test('빌드 번호(+115)가 붙어 있어도 앞부분만 본다', () {
      expect(gate(min: '0.4.6').blocks('0.4.5+114'), isTrue);
      expect(gate(min: '0.4.6+120').blocks('0.4.6'), isFalse);
    });

    test('설정이 이상하면 막지 않는다(fail-open)', () {
      // 오타·형식 오류로 이미 설치된 앱이 전부 잠기면 안 된다.
      for (final bad in ['', '   ', 'v0.4.6', '최신', '0.4.x', '1,0,0']) {
        expect(
          gate(min: bad).blocks('0.0.1'),
          isFalse,
          reason: 'minSupportedVersion="$bad"',
        );
      }
      // 앱 버전 쪽이 이상해도 마찬가지.
      expect(gate(min: '0.4.6').blocks('unknown'), isFalse);
    });

    test('forceUpgrade는 버전과 무관하게 모두 막는다', () {
      expect(gate(force: true).blocks('99.99.99'), isTrue);
      expect(gate(force: true, min: '0.0.1').blocks('99.0.0'), isTrue);
    });

    test('기본값(disabled)은 어떤 버전도 막지 않는다', () {
      expect(AppGateConfig.disabled.blocks('0.0.1'), isFalse);
    });
  });

  group('배포 설정 정합성', () {
    test('AppInfo.appVersion이 pubspec.yaml과 같다', () {
      // 게이트가 이 값으로 자기 버전을 판단하므로 어긋나면 엉뚱한 기기가
      // 잠기거나 잠기지 않는다(실제로 0.4.1에 멈춰 있던 적이 있다).
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(
        r'^version:\s*([0-9.]+)\+',
        multiLine: true,
      ).firstMatch(pubspec);
      expect(m, isNotNull, reason: 'pubspec.yaml의 version 형식이 바뀌었다');
      expect(AppInfo.appVersion, m!.group(1));
    });

    test('public_data/app_gate.json이 현재 앱 버전을 막지 않는다', () {
      // 저장소에 커밋된 사본이 지금 빌드를 잠그는 상태면, 그대로 공개
      // 저장소에 올렸을 때 모두가 못 켠다.
      final json =
          jsonDecode(File('public_data/app_gate.json').readAsStringSync())
              as Map<String, dynamic>;
      final config = AppGateConfig.fromJson(json);
      expect(
        config.blocks(AppInfo.appVersion),
        isFalse,
        reason:
            'app_gate.json이 현재 버전(${AppInfo.appVersion})을 막는다 — '
            'minSupportedVersion=${config.minSupportedVersion}',
      );
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
