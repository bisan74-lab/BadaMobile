/// `LatestOnlyRunner`가 실제로 "겹치는 요청을 최신 것만 흡수"하는지 검증한다.
///
/// 실제 원인(바람지도 히트맵 재굽기)은 `compute()` 아이솔레이트를 쓰므로
/// 여기서 재현하면 느리고 CI에서 들쭉날쭉해진다. 대신 인위적으로 제어되는
/// `Completer` 기반 가짜 작업으로 조율 로직 자체만 떼어 검증한다 — 시간에
/// 의존하지 않아 결정적이다.
library;

import 'dart:async';

import 'package:bada_mobile/core/utils/latest_only_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('실행 중이 아니면 즉시 돈다', () async {
    final runner = LatestOnlyRunner();
    var calls = 0;
    final done = Completer<void>();
    runner.run(() async {
      calls++;
      done.complete();
    });
    await done.future;
    expect(calls, 1);
  });

  test('실행 중에 여러 번 요청해도 실행이 끝난 뒤 딱 한 번만 더 돈다', () async {
    // 첫 실행이 끝나기 전에 5번을 더 요청한다 — 다 무시되고 끝난 뒤 1번만
    // 이어서 돌아야 한다(중간값 건너뛰기가 실제로 일어나는지의 핵심 검증).
    final runner = LatestOnlyRunner();
    var calls = 0;
    final firstStarted = Completer<void>();
    final firstMayFinish = Completer<void>();
    final secondDone = Completer<void>();

    runner.run(() async {
      calls++;
      if (calls == 1) {
        firstStarted.complete();
        await firstMayFinish.future;
      } else {
        secondDone.complete();
      }
    });

    await firstStarted.future; // 첫 작업이 진짜 "실행 중" 상태가 됐다.

    // 이 사이에 다섯 번 더 요청한다 — 첫 작업이 아직 안 끝났으므로 전부
    // "dirty만 세우고 반환"이어야 하며, 새 작업이 새로 시작되면 안 된다.
    for (var i = 0; i < 5; i++) {
      runner.run(() async {
        // 이 클로저 자체가 실행되면(=중간에 새 아이솔레이트가 떴다는 뜻)
        // calls가 여기서도 올라가므로 아래 최종 assert에서 3 이상으로 잡힌다.
        calls++;
      });
    }
    expect(calls, 1, reason: '실행 중에는 새 작업이 시작되면 안 된다');

    firstMayFinish.complete(); // 첫 작업을 끝낸다.
    await secondDone.future; // dirty 흡수로 이어서 도는 두 번째 작업.

    expect(
      calls,
      2,
      reason: '중간의 5번 요청은 흡수되고, 첫 실행 + 마지막 한 번만 돌아야 한다',
    );
  });

  test('두 번째 실행 도중에도 또 쌓이면 세 번째까지 이어서 돈다', () async {
    final runner = LatestOnlyRunner();
    var calls = 0;
    final firstStarted = Completer<void>();
    final firstMayFinish = Completer<void>();
    final secondStarted = Completer<void>();
    final secondMayFinish = Completer<void>();
    final thirdDone = Completer<void>();

    runner.run(() async {
      calls++;
      if (calls == 1) {
        firstStarted.complete();
        await firstMayFinish.future;
      } else if (calls == 2) {
        secondStarted.complete();
        await secondMayFinish.future;
      } else {
        thirdDone.complete();
      }
    });

    await firstStarted.future;
    runner.run(() async {}); // 첫 실행 중 요청 → dirty
    firstMayFinish.complete();

    await secondStarted.future; // dirty 흡수로 두 번째 실행 시작됨.
    runner.run(() async {}); // 두 번째 실행 중에도 또 요청 → dirty
    secondMayFinish.complete();

    await thirdDone.future;
    expect(calls, 3);
  });
}
