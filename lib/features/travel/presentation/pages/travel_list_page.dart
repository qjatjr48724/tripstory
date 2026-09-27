import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// 여행 목록 화면 스켈레톤
/// 여행 생성 / 초대코드 참여는 4단계에서 구현한다.
class TravelListPage extends ConsumerWidget {
  const TravelListPage({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authRepositoryProvider).signOut();
    } on AppAuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(authRepositoryProvider).currentUser?.email;

    return Scaffold(
      appBar: AppBar(
        title: const Text('내 여행'),
        actions: [
          IconButton(
            tooltip: '로그아웃',
            onPressed: () => _signOut(context, ref),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (email != null) ...[
                Text(
                  email,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
              ],
              Icon(
                Icons.flight_takeoff,
                size: 56,
                color: AppColors.primary.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 16),
              Text(
                '아직 여행이 없어요',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '새 여행을 만들거나\n초대코드로 참여해 보세요',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('여행 생성은 4단계에서 구현됩니다')),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('여행 만들기'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('초대코드 참여는 4단계에서 구현됩니다')),
                  );
                },
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('초대코드로 참여'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
