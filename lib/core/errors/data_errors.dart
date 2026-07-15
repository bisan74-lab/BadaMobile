/// 데이터 제공 범위를 벗어난 요청에 대한 도메인 예외.
class DataRangeException implements Exception {
  const DataRangeException(this.message);

  final String message;

  @override
  String toString() => message;
}
