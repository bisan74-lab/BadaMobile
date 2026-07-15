// 공공데이터포털(KHOA 미러) API 연결 진단 스크립트.
//
// 사용법:
//   dart run tool/check_api.dart <서비스키>
//
// 조석예보(고저조)·바다낚시지수 API를 파라미터 표기 조합별로 호출해
// 상태코드와 응답 앞부분을 출력한다. 어떤 조합이 성공하는지 확인해
// 리포지토리 구현의 파라미터를 확정하는 용도.
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('사용법: dart run tool/check_api.dart <서비스키>');
    exit(1);
  }
  final key = args.first;
  final today = DateTime.now();
  final ymd =
      '${today.year}'
      '${today.month.toString().padLeft(2, '0')}'
      '${today.day.toString().padLeft(2, '0')}';

  final cases = <String, Uri>{
    '조석예보 serviceKey(소문자)': Uri.https(
      'apis.data.go.kr',
      '/1192136/tideFcstHghLw/GetTideFcstHghLwApiService',
      {
        'serviceKey': key,
        'ObsCode': 'DT_0001',
        'Date': ymd,
        'ResultType': 'json',
      },
    ),
    '조석예보 ServiceKey(대문자)': Uri.https(
      'apis.data.go.kr',
      '/1192136/tideFcstHghLw/GetTideFcstHghLwApiService',
      {
        'ServiceKey': key,
        'ObsCode': 'DT_0001',
        'Date': ymd,
        'ResultType': 'json',
      },
    ),
    '조석예보 오퍼레이션 없이': Uri.https('apis.data.go.kr', '/1192136/tideFcstHghLw', {
      'serviceKey': key,
      'ObsCode': 'DT_0001',
      'Date': ymd,
      'ResultType': 'json',
    }),
    '낚시지수 serviceKey(소문자)': Uri.https(
      'apis.data.go.kr',
      '/1192136/fcstFishingv2/GetFcstFishingApiService',
      {'serviceKey': key, 'ResultType': 'json'},
    ),
    '낚시지수 오퍼레이션 없이': Uri.https('apis.data.go.kr', '/1192136/fcstFishingv2', {
      'serviceKey': key,
      'ResultType': 'json',
    }),
  };

  final client = HttpClient();
  for (final entry in cases.entries) {
    try {
      final req = await client.getUrl(entry.value);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final head = body.replaceAll('\n', ' ');
      print('--- ${entry.key}');
      print('    HTTP ${res.statusCode}');
      print('    ${head.substring(0, head.length > 400 ? 400 : head.length)}');
    } catch (e) {
      print('--- ${entry.key}');
      print('    오류: $e');
    }
    print('');
  }
  client.close();
  print('성공한 조합의 전체 응답을 개발 담당(Claude 세션)에 붙여넣어 주세요.');
}
