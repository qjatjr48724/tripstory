/// ISO 3166-1 alpha-2 → 국기 이모지 (추가 패키지 없이)
String countryFlagEmoji(String? countryCode) {
  if (countryCode == null) return '🏳️';
  var code = countryCode.trim().toUpperCase();
  if (code == 'KOR') code = 'KR';
  if (code == 'JPN') code = 'JP';
  if (code == 'USA') code = 'US';
  if (code.length != 2) return '🏳️';
  final a = code.codeUnitAt(0);
  final b = code.codeUnitAt(1);
  if (a < 0x41 || a > 0x5A || b < 0x41 || b > 0x5A) return '🏳️';
  return String.fromCharCodes([
    0x1F1E6 + (a - 0x41),
    0x1F1E6 + (b - 0x41),
  ]);
}
