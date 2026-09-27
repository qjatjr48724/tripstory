import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';

class AppAuthException implements Exception {
  AppAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _requireClient {
    final client = _client;
    if (client == null || !Env.isSupabaseReady) {
      throw AppAuthException('Supabase가 설정되지 않았습니다.');
    }
    return client;
  }

  Session? get currentSession {
    if (!Env.isSupabaseReady) return null;
    return _client?.auth.currentSession;
  }

  User? get currentUser {
    if (!Env.isSupabaseReady) return null;
    return _client?.auth.currentUser;
  }

  Stream<AuthState> get onAuthStateChange {
    if (!Env.isSupabaseReady || _client == null) {
      return const Stream.empty();
    }
    return _client.auth.onAuthStateChange;
  }

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _requireClient.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AppAuthException {
      rethrow;
    } on AuthApiException catch (e) {
      throw AppAuthException(_mapAuthMessage(e.message));
    } catch (_) {
      throw AppAuthException('로그인에 실패했습니다. 잠시 후 다시 시도해주세요.');
    }
  }

  /// 이메일 가입. 이메일 인증이 켜져 있으면 [session]이 null일 수 있다.
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      return await _requireClient.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'display_name': displayName.trim()},
      );
    } on AppAuthException {
      rethrow;
    } on AuthApiException catch (e) {
      throw AppAuthException(_mapAuthMessage(e.message));
    } catch (_) {
      throw AppAuthException('회원가입에 실패했습니다. 잠시 후 다시 시도해주세요.');
    }
  }

  Future<void> signOut() async {
    await _requireClient.auth.signOut();
  }

  Future<void> resendSignupEmail(String email) async {
    try {
      await _requireClient.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
      );
    } on AuthApiException catch (e) {
      throw AppAuthException(_mapAuthMessage(e.message));
    } catch (_) {
      throw AppAuthException('인증 메일 재발송에 실패했습니다.');
    }
  }

  String _mapAuthMessage(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('invalid login credentials')) {
      return '이메일 또는 비밀번호가 올바르지 않습니다.';
    }
    if (lower.contains('email not confirmed')) {
      return '이메일 인증이 완료되지 않았습니다. 메일함을 확인해주세요.';
    }
    if (lower.contains('user already registered')) {
      return '이미 가입된 이메일입니다.';
    }
    if (lower.contains('password')) {
      return '비밀번호는 6자 이상이어야 합니다.';
    }
    if (lower.contains('rate limit') ||
        lower.contains('too many') ||
        lower.contains('over_email_send_rate_limit')) {
      return '인증 메일 발송 제한에 걸렸습니다. 수 분~1시간 뒤 다시 시도하거나, '
          '개발 중에는 Supabase Authentication → Providers → Email에서 '
          'Confirm email을 꺼보세요.';
    }
    return raw;
  }
}
