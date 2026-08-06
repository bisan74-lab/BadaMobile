/// 성능 측정 공용 도구.
///
/// **왜 시간이 아니라 횟수를 먼저 재는가.** CI 러너의 시간 측정은 들쭉날쭉해서
/// "몇 ms 이하" 같은 단언은 금방 깨진다(그리고 깨지면 사람들이 무시하게 된다).
/// 반면 **HTTP 요청 몇 건 / 픽셀 몇 개 / Path 몇 번 생성**은 결정적이라
/// 회귀를 정확히 잡는다. 그래서 이 파일은
///
/// - **횟수**는 `expect`로 못박고,
/// - **시간**은 표로 찍어 사람이 개선 전후를 비교하게 한다.
///
/// 시간 단언은 하지 않는다.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

/// 요청 수와 URL을 세는 http 클라이언트.
///
/// 지연을 [latency]로 흉내 낼 수 있어, "요청 5건을 병렬로 던지면 총 얼마"
/// 같은 것을 네트워크 없이 재현할 수 있다.
class CountingClient extends http.BaseClient {
  CountingClient({required this.respond, this.latency = Duration.zero});

  /// 요청 URL을 받아 응답 본문을 돌려준다.
  final String Function(Uri uri) respond;

  /// 요청 하나당 걸리는 시간(실제 서버 왕복을 흉내).
  final Duration latency;

  final List<Uri> requests = [];

  /// 호스트+경로별 요청 수. `host/path` 형태가 키다.
  Map<String, int> get byEndpoint {
    final out = <String, int>{};
    for (final u in requests) {
      final k = '${u.host}${u.path}';
      out[k] = (out[k] ?? 0) + 1;
    }
    return out;
  }

  int get count => requests.length;

  void reset() => requests.clear();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final body = respond(request.url);
    return http.StreamedResponse(
      Stream.value(body.codeUnits),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

/// 측정값 한 줄.
class Measurement {
  Measurement(this.label, this.elapsed, {this.detail = ''});

  final String label;
  final Duration elapsed;
  final String detail;
}

/// 여러 번 돌려 **중앙값**을 잡는다. 평균은 첫 회 워밍업에 끌려간다.
Future<Measurement> measure(
  String label,
  Future<void> Function() body, {
  int runs = 5,
  String detail = '',
}) async {
  final samples = <int>[];
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    await body();
    sw.stop();
    samples.add(sw.elapsedMicroseconds);
  }
  samples.sort();
  return Measurement(
    label,
    Duration(microseconds: samples[samples.length ~/ 2]),
    detail: detail,
  );
}

/// 사람이 읽을 표로 찍는다. 개선 전후를 눈으로 비교하는 것이 목적이다.
void printReport(String title, List<Measurement> rows) {
  // ignore: avoid_print — 이 파일의 출력이 곧 리포트다.
  void out(String s) => print(s);

  final width = rows.fold<int>(
    12,
    (w, r) => r.label.length > w ? r.label.length : w,
  );
  out('\n■ $title');
  out('${'항목'.padRight(width)}  ${'중앙값'.padLeft(10)}   비고');
  out('${'─' * width}  ${'─' * 10}   ${'─' * 30}');
  for (final r in rows) {
    final ms = (r.elapsed.inMicroseconds / 1000).toStringAsFixed(1);
    out('${r.label.padRight(width)}  ${'$ms ms'.padLeft(10)}   ${r.detail}');
  }
  out('');
}
