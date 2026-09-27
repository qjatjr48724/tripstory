import 'package:flutter/material.dart';

/// tripstory 브랜드 컬러
///
/// 여행·바다·하늘을 연상하는 청록·네이비 계열.
/// 기본 Material purple / cream+terracotta 톤은 사용하지 않는다.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF0D7377);
  static const Color primaryDark = Color(0xFF095456);
  static const Color primaryLight = Color(0xFF14919B);

  static const Color secondary = Color(0xFFE29578);
  static const Color accent = Color(0xFF212E53);

  static const Color background = Color(0xFFF7F9F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEEF3F3);

  static const Color textPrimary = Color(0xFF1A2332);
  static const Color textSecondary = Color(0xFF5A6577);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  static const Color border = Color(0xFFD5DEDE);
  static const Color error = Color(0xFFC44536);
  static const Color success = Color(0xFF2A9D8F);
  static const Color warning = Color(0xFFE9A825);

  /// 이탈한 구성원 장소용 비활성 색
  static const Color inactiveMember = Color(0xFF9AA3B2);
}
