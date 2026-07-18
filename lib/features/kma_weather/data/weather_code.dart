/// WMO 날씨 해석 코드(Open-Meteo `weather_code`)를 한글 라벨·아이콘 종류로
/// 매핑한다. 기상청 하늘상태(SKY)·강수형태(PTY)도 이 코드 체계로 환산해
/// 하나의 표현으로 합친다.
enum WeatherIconKind {
  clear,
  partlyCloudy,
  cloudy,
  fog,
  drizzle,
  rain,
  snow,
  sleet,
  thunder,
}

/// WMO 코드 → 한글 라벨.
String wmoLabelKo(int code) {
  switch (code) {
    case 0:
      return '맑음';
    case 1:
      return '대체로 맑음';
    case 2:
      return '구름 조금';
    case 3:
      return '흐림';
    case 45:
    case 48:
      return '안개';
    case 51:
    case 53:
    case 55:
      return '가랑비';
    case 56:
    case 57:
      return '어는 가랑비';
    case 61:
    case 63:
    case 65:
      return '비';
    case 66:
    case 67:
      return '어는 비';
    case 71:
    case 73:
    case 75:
      return '눈';
    case 77:
      return '싸락눈';
    case 80:
    case 81:
    case 82:
      return '소나기';
    case 85:
    case 86:
      return '소낙눈';
    case 95:
      return '뇌우';
    case 96:
    case 99:
      return '우박 동반 뇌우';
    default:
      return '-';
  }
}

/// WMO 코드 → 아이콘 종류.
WeatherIconKind wmoIcon(int code) {
  switch (code) {
    case 0:
    case 1:
      return WeatherIconKind.clear;
    case 2:
      return WeatherIconKind.partlyCloudy;
    case 3:
      return WeatherIconKind.cloudy;
    case 45:
    case 48:
      return WeatherIconKind.fog;
    case 51:
    case 53:
    case 55:
    case 56:
    case 57:
      return WeatherIconKind.drizzle;
    case 61:
    case 63:
    case 65:
    case 66:
    case 67:
    case 80:
    case 81:
    case 82:
      return WeatherIconKind.rain;
    case 71:
    case 73:
    case 75:
    case 85:
    case 86:
      return WeatherIconKind.snow;
    case 77:
      return WeatherIconKind.sleet;
    case 95:
    case 96:
    case 99:
      return WeatherIconKind.thunder;
    default:
      return WeatherIconKind.cloudy;
  }
}

/// 2시간 이내 강수 종류(비/진눈깨비/눈/우박/가랑비) 한글 표기. 강수 없으면 null.
String? precipKindKo(int code) {
  switch (wmoIcon(code)) {
    case WeatherIconKind.drizzle:
      return '가랑비';
    case WeatherIconKind.rain:
      return '비';
    case WeatherIconKind.snow:
      return '눈';
    case WeatherIconKind.sleet:
      return '진눈깨비';
    case WeatherIconKind.thunder:
      return code >= 96 ? '우박' : '뇌우';
    default:
      return null;
  }
}

/// 기상청 SKY(1/3/4)+PTY(0~7)를 근사 WMO 코드로 환산한다(기상청 우선 병합용).
int kmaToWmo({required int sky, required int pty}) {
  if (pty != 0) {
    switch (pty) {
      case 1: // 비
        return 63;
      case 2: // 비/눈 → 진눈깨비 근사
        return 77;
      case 3: // 눈
        return 73;
      case 4: // 소나기
        return 81;
      case 5: // 빗방울
        return 51;
      case 6: // 빗방울/눈날림 → 진눈깨비 근사
        return 77;
      case 7: // 눈날림
        return 75;
    }
  }
  switch (sky) {
    case 1:
      return 0;
    case 3:
      return 2;
    case 4:
      return 3;
    default:
      return 2;
  }
}
