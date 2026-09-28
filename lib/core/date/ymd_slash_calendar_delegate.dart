import 'package:flutter/material.dart';

/// 날짜 직접 입력: `yyyy/MM/dd` 또는 `yyyyMMdd` (예: 20261002)
class YmdSlashCalendarDelegate extends GregorianCalendarDelegate {
  const YmdSlashCalendarDelegate();

  static final RegExp _slashPattern = RegExp(r'^(\d{4})/(\d{1,2})/(\d{1,2})$');
  static final RegExp _digitsPattern = RegExp(r'^(\d{4})(\d{2})(\d{2})$');

  @override
  String formatCompactDate(
    DateTime date,
    MaterialLocalizations localizations,
  ) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  @override
  DateTime? parseCompactDate(
    String? inputString,
    MaterialLocalizations localizations,
  ) {
    if (inputString == null) return null;
    final trimmed = inputString.trim();

    final Match? match = _slashPattern.firstMatch(trimmed) ??
        _digitsPattern.firstMatch(trimmed);
    if (match == null) return null;

    return _buildDate(
      year: int.tryParse(match.group(1)!),
      month: int.tryParse(match.group(2)!),
      day: int.tryParse(match.group(3)!),
    );
  }

  DateTime? _buildDate({
    required int? year,
    required int? month,
    required int? day,
  }) {
    if (year == null || month == null || day == null) return null;
    if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }

    final parsed = DateTime(year, month, day);
    // 2월 31일 등 잘못된 날짜는 DateTime이 넘어가므로 검증
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  @override
  String dateHelpText(MaterialLocalizations localizations) =>
      'yyyy/mm/dd 또는 yyyymmdd';
}
