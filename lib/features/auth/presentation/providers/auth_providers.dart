import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../data/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final client = Env.isSupabaseReady ? Supabase.instance.client : null;
  return AuthRepository(client);
});

/// 현재 세션 스트림 (초기값 포함)
final authStateProvider = StreamProvider<Session?>((ref) async* {
  final repo = ref.watch(authRepositoryProvider);
  yield repo.currentSession;
  yield* repo.onAuthStateChange.map((event) => event.session);
});

final currentSessionProvider = Provider<Session?>((ref) {
  final async = ref.watch(authStateProvider);
  return async.when(
    data: (session) => session,
    loading: () => ref.read(authRepositoryProvider).currentSession,
    error: (_, _) => null,
  );
});

final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(currentSessionProvider) != null;
});

/// GoRouter refresh용 — auth 변경 시 notify
class AuthRefreshListenable extends ChangeNotifier {
  AuthRefreshListenable(Ref ref) {
    _subscription = ref.listen(authStateProvider, (_, _) {
      notifyListeners();
    });
  }

  late final ProviderSubscription<AsyncValue<Session?>> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

final authRefreshListenableProvider = Provider<AuthRefreshListenable>((ref) {
  final listenable = AuthRefreshListenable(ref);
  ref.onDispose(listenable.dispose);
  return listenable;
});
