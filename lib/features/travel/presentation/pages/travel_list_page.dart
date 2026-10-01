import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/roles.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/travel_repository.dart';
import '../../domain/travel.dart';
import '../providers/travel_providers.dart';

class TravelListPage extends ConsumerStatefulWidget {
  const TravelListPage({super.key});

  @override
  ConsumerState<TravelListPage> createState() => _TravelListPageState();
}

class _TravelListPageState extends ConsumerState<TravelListPage>
    with RouteAware {
  bool _routeSubscribed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshTravels());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      appRouteObserver.unsubscribe(this);
    }
    super.dispose();
  }

  /// 상세·구성원 화면에서 돌아올 때 (중첩 라우트로 목록 State가 유지됨)
  @override
  void didPopNext() => _refreshTravels();

  void _refreshTravels() {
    if (!mounted) return;
    ref.invalidate(myTravelsProvider);
  }

  Future<void> _signOut() async {
    try {
      await ref.read(authRepositoryProvider).signOut();
    } on AppAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _joinWithCode() async {
    final code = await showDialog<String>(
      context: context,
      builder: (context) => const _InviteCodeDialog(),
    );
    if (code == null || code.isEmpty || !mounted) return;

    try {
      final travel =
          await ref.read(travelRepositoryProvider).joinByInviteCode(code);
      ref.invalidate(myTravelsProvider);
      if (!mounted) return;
      final pending = travel.isJoinPending;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pending
                ? '참가 요청을 보냈어요. 여행장 승인을 기다려 주세요.'
                : '여행에 참여했습니다.',
          ),
        ),
      );
      context.go('${AppRoutes.travels}/${travel.id}');
    } on TravelException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncTravels = ref.watch(myTravelsProvider);
    final email = ref.watch(authRepositoryProvider).currentUser?.email;
    final dateFormat = DateFormat('MM.dd');

    return Scaffold(
      appBar: AppBar(
        title: const Text('내 여행'),
        actions: [
          IconButton(
            tooltip: '로그아웃',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.createTravel),
        icon: const Icon(Icons.add),
        label: const Text('여행 만들기'),
      ),
      body: asyncTravels.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$e', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => ref.invalidate(myTravelsProvider),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
        data: (travels) {
          if (travels.isEmpty) {
            return _EmptyTravels(
              email: email,
              onCreate: () => context.push(AppRoutes.createTravel),
              onJoin: _joinWithCode,
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myTravelsProvider);
              await ref.read(myTravelsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              children: [
                if (email != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12, left: 4),
                    child: Text(
                      email,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _joinWithCode,
                    icon: const Icon(Icons.group_add_outlined, size: 20),
                    label: const Text('초대코드로 참여'),
                  ),
                ),
                const SizedBox(height: 4),
                ...travels.map(
                  (travel) => _TravelCard(
                    travel: travel,
                    dateFormat: dateFormat,
                    onTap: () =>
                        context.push('${AppRoutes.travels}/${travel.id}'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EmptyTravels extends StatelessWidget {
  const _EmptyTravels({
    required this.email,
    required this.onCreate,
    required this.onJoin,
  });

  final String? email;
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (email != null) ...[
              Text(email!, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
            ],
            Text(
              '새 여행을 만들거나\n초대코드로 참여해 보세요',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('여행 만들기'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onJoin,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('초대코드로 참여'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteCodeDialog extends StatefulWidget {
  const _InviteCodeDialog();

  @override
  State<_InviteCodeDialog> createState() => _InviteCodeDialogState();
}

class _InviteCodeDialogState extends State<_InviteCodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('초대코드로 참여'),
      content: TextField(
        controller: _controller,
        maxLength: AppConstants.inviteCodeLength,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '초대코드 6자리',
          hintText: '영문·숫자',
          counterText: '',
        ),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('참여'),
        ),
      ],
    );
  }
}

class _TravelCard extends StatelessWidget {
  const _TravelCard({
    required this.travel,
    required this.dateFormat,
    required this.onTap,
  });

  final Travel travel;
  final DateFormat dateFormat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      travel.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (travel.isJoinPending)
                    Text(
                      '승인 대기',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                    )
                  else if (travel.myRole != null)
                    Text(
                      travel.myRole!.label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.primary,
                          ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                travel.region,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${dateFormat.format(travel.startDate)} ~ '
                '${dateFormat.format(travel.endDate)}'
                '${travel.status == TravelStatus.completed ? ' · 완료' : ''}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
