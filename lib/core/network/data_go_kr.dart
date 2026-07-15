import 'dart:convert';

/// 공공데이터포털(data.go.kr) 공통 응답 봉투 파서.
///
/// 표준 구조: response.header.resultCode == '00',
///           response.body.items.item = [...]
List<Map<String, dynamic>> parseDataGoKrItems(String body) {
  final root = jsonDecode(body) as Map<String, dynamic>;
  final response = root['response'] as Map<String, dynamic>?;
  if (response == null) {
    throw const FormatException('data.go.kr 응답에 response 필드가 없음');
  }
  final header = response['header'] as Map<String, dynamic>?;
  final resultCode = header?['resultCode']?.toString();
  if (resultCode != null && resultCode != '00') {
    throw FormatException(
      'data.go.kr 오류 응답: $resultCode ${header?['resultMsg'] ?? ''}',
    );
  }
  final items = (response['body'] as Map<String, dynamic>?)?['items'];
  final List<dynamic> itemList;
  if (items is List) {
    itemList = items;
  } else if (items is Map<String, dynamic>) {
    final item = items['item'];
    itemList = item is List ? item : (item == null ? const [] : [item]);
  } else {
    itemList = const [];
  }
  return itemList.whereType<Map<String, dynamic>>().toList();
}

/// 여러 후보 키 중 첫 번째로 존재하는 값을 돌려준다.
/// 공공데이터 API마다 필드 명명(camel/snake)이 달라 후보 매칭으로 흡수한다.
Object? pickField(Map<String, dynamic> item, List<String> candidates) {
  for (final key in candidates) {
    final v = item[key];
    if (v != null) return v;
  }
  return null;
}
