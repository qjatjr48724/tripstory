import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/roles.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/travel_repository.dart';
import '../../domain/travel.dart';
import '../../domain/travel_member.dart';
import '../providers/travel_providers.dart';

class TravelMembersPage extends ConsumerWidget {
  const TravelMembersPage({super.key, required this.travelId});

  final String travelId;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(travelMembersProvider(travelId));
    ref.invalidate(travelDetailProvider(travelId));
    ref.invalidate(pendingOwnershipTransferProvider(travelId));
    ref.invalidate(myTravelsProvider);
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    try {
      await action();
      await _refresh(ref);
      if (!context.mounted) return;
      if (successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
    } on TravelException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final travelAsync = ref.watch(travelDetailProvider(travelId));
    final membersAsync = ref.watch(travelMembersProvider(travelId));
    final transferAsync =
        ref.watch(pendingOwnershipTransferProvider(travelId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('구성원'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('${AppRoutes.travels}/$travelId'),
        ),
      ),
      body: travelAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (travel) {
          return membersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (members) {
              final myRole = travel.myRole;
              final pending = transferAsync.asData?.value;
              final activeMembers =
                  members.where((m) => m.status == MemberStatus.active).toList();
              final joinRequests = members
                  .where((m) => m.status == MemberStatus.pending)
                  .toList();
              final me = activeMembers.where((m) => m.isMe).firstOrNull;

              return RefreshIndicator(
                onRefresh: () => _refresh(ref),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    if (pending != null && me != null)
                      _TransferBanner(
                        request: pending,
                        members: activeMembers,
                        me: me,
                        onAccept: () => _run(
                          context,
                          ref,
                          () => ref
                              .read(travelRepositoryProvider)
                              .respondOwnershipTransfer(
                                requestId: pending.id,
                                accept: true,
                              ),
                          successMessage: '여행장이 이전되었습니다',
                        ),
                        onReject: () => _run(
                          context,
                          ref,
                          () => ref
                              .read(travelRepositoryProvider)
                              .respondOwnershipTransfer(
                                requestId: pending.id,
                                accept: false,
                              ),
                          successMessage: '이전 요청을 거절했습니다',
                        ),
                        onCancel: () => _run(
                          context,
                          ref,
                          () => ref
                              .read(travelRepositoryProvider)
                              .cancelOwnershipTransfer(pending.id),
                          successMessage: '이전 요청을 취소했습니다',
                        ),
                      ),
                    if (myRole == TravelRole.owner &&
                        joinRequests.isNotEmpty) ...[
                      Text(
                        '참가 요청 ${joinRequests.length}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ...joinRequests.map(
                        (member) => Card(
                          child: ListTile(
                            title: Text(member.displayName),
                            subtitle: const Text('초대코드로 참가 요청'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () => _run(
                                    context,
                                    ref,
                                    () => ref
                                        .read(travelRepositoryProvider)
                                        .rejectTravelJoin(member.id),
                                    successMessage: '참가 요청을 거절했습니다',
                                  ),
                                  child: const Text('거절'),
                                ),
                                FilledButton(
                                  onPressed: () => _run(
                                    context,
                                    ref,
                                    () => ref
                                        .read(travelRepositoryProvider)
                                        .acceptTravelJoin(member.id),
                                    successMessage:
                                        '${member.displayName}님을 수락했습니다',
                                  ),
                                  child: const Text('수락'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Text(
                      '구성원 ${activeMembers.length}명',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ...activeMembers.map(
                      (member) => _MemberTile(
                        member: member,
                        myRole: myRole,
                        travelEditable: travel.status == TravelStatus.active,
                        onAssignTreasurer: () => _run(
                          context,
                          ref,
                          () => ref
                              .read(travelRepositoryProvider)
                              .assignTreasurer(
                                travelId: travelId,
                                memberId: member.id,
                              ),
                          successMessage: '${member.displayName}님을 총무로 지정했습니다',
                        ),
                        onRemoveTreasurer: () => _run(
                          context,
                          ref,
                          () => ref
                              .read(travelRepositoryProvider)
                              .assignTreasurer(
                                travelId: travelId,
                                memberId: null,
                              ),
                          successMessage: '총무를 해제했습니다',
                        ),
                        onKick: () => _confirmKick(
                          context,
                          ref,
                          member,
                        ),
                        onTransfer: () => _run(
                          context,
                          ref,
                          () => ref
                              .read(travelRepositoryProvider)
                              .requestOwnershipTransfer(
                                travelId: travelId,
                                toMemberId: member.id,
                              ),
                          successMessage: '여행장 이전을 요청했습니다',
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (myRole?.canReissueInviteCode == true &&
                        travel.status == TravelStatus.active)
                      OutlinedButton.icon(
                        onPressed: () => _confirmReissue(context, ref, travel),
                        icon: const Icon(Icons.refresh),
                        label: const Text('초대코드 재발급'),
                      ),
                    if (travel.status == TravelStatus.active &&
                        myRole != null &&
                        (myRole != TravelRole.owner ||
                            activeMembers.length == 1)) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => _confirmLeave(
                          context,
                          ref,
                          isSoloOwner: myRole == TravelRole.owner &&
                              activeMembers.length == 1,
                        ),
                        child: Text(
                          myRole == TravelRole.owner &&
                                  activeMembers.length == 1
                              ? '여행 나가기 (삭제)'
                              : '여행 나가기',
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                    ],
                    if (myRole == TravelRole.owner &&
                        activeMembers.length > 1) ...[
                      const SizedBox(height: 8),
                      Text(
                        '다른 구성원이 있을 때 여행장은 소유권을 이전한 뒤에만 나갈 수 있습니다.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmKick(
    BuildContext context,
    WidgetRef ref,
    TravelMember member,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('강제 퇴장'),
        content: Text(
          '${member.displayName}님을 이 여행에서 퇴장시킬까요?\n'
          '작성한 장소·기록은 남습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('퇴장', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(travelRepositoryProvider).kickMember(
            travelId: travelId,
            memberId: member.id,
          ),
      successMessage: '${member.displayName}님을 퇴장시켰습니다',
    );
  }

  Future<void> _confirmLeave(
    BuildContext context,
    WidgetRef ref, {
    bool isSoloOwner = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isSoloOwner ? '여행 나가기' : '여행 나가기'),
        content: Text(
          isSoloOwner
              ? '구성원이 자신뿐인 여행입니다.\n'
                  '나가면 이 여행은 휴지통으로 이동하며 7일 후 영구 삭제됩니다. 계속할까요?'
              : '이 여행에서 나갈까요?\n작성한 장소·기록은 여행에 남습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('나가기', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(travelRepositoryProvider).leaveTravel(travelId);
      ref.invalidate(myTravelsProvider);
      if (!context.mounted) return;
      context.go(AppRoutes.travels);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isSoloOwner ? '여행을 휴지통으로 옮겼습니다' : '여행에서 나갔습니다',
          ),
        ),
      );
    } on TravelException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _confirmReissue(
    BuildContext context,
    WidgetRef ref,
    Travel travel,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('초대코드 재발급'),
        content: const Text(
          '새 초대코드를 발급하면 기존 코드는 즉시 무효화됩니다. 계속할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('재발급'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(
      context,
      ref,
      () async {
        await ref.read(travelRepositoryProvider).reissueInviteCode(travelId);
      },
      successMessage: '초대코드를 재발급했습니다',
    );
  }
}

class _TransferBanner extends StatelessWidget {
  const _TransferBanner({
    required this.request,
    required this.members,
    required this.me,
    required this.onAccept,
    required this.onReject,
    required this.onCancel,
  });

  final OwnershipTransferRequest request;
  final List<TravelMember> members;
  final TravelMember me;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final from = members.where((m) => m.id == request.fromMemberId).firstOrNull;
    final to = members.where((m) => m.id == request.toMemberId).firstOrNull;
    final isTarget = me.id == request.toMemberId;
    final isRequester = me.id == request.fromMemberId;

    if (!isTarget && !isRequester) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '여행장 이전 요청',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            isTarget
                ? '${from?.displayName ?? '여행장'}님이 여행장 권한을 넘기려 합니다.'
                : '${to?.displayName ?? '구성원'}님의 수락을 기다리는 중입니다.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (isTarget)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    child: const Text('거절'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAccept,
                    child: const Text('수락'),
                  ),
                ),
              ],
            )
          else
            OutlinedButton(
              onPressed: onCancel,
              child: const Text('요청 취소'),
            ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.myRole,
    required this.travelEditable,
    required this.onAssignTreasurer,
    required this.onRemoveTreasurer,
    required this.onKick,
    required this.onTransfer,
  });

  final TravelMember member;
  final TravelRole? myRole;
  final bool travelEditable;
  final VoidCallback onAssignTreasurer;
  final VoidCallback onRemoveTreasurer;
  final VoidCallback onKick;
  final VoidCallback onTransfer;

  Color _parseColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16) ?? 0x0D7377;
    return Color(0xFF000000 | value);
  }

  String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCodes(trimmed.runes.take(1));
  }

  @override
  Widget build(BuildContext context) {
    final canManage = myRole?.canKickMember == true &&
        travelEditable &&
        !member.isMe &&
        member.role != TravelRole.owner;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _parseColor(member.colorHex),
          child: Text(
            _initial(member.displayName),
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                member.displayName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (member.isMe) ...[
              const SizedBox(width: 6),
              Text(
                '(나)',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
        subtitle: Text(member.role.label),
        trailing: canManage
            ? PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'treasurer':
                      onAssignTreasurer();
                    case 'untreasurer':
                      onRemoveTreasurer();
                    case 'transfer':
                      onTransfer();
                    case 'kick':
                      onKick();
                  }
                },
                itemBuilder: (context) => [
                  if (member.role != TravelRole.treasurer)
                    const PopupMenuItem(
                      value: 'treasurer',
                      child: Text('총무로 지정'),
                    ),
                  if (member.role == TravelRole.treasurer)
                    const PopupMenuItem(
                      value: 'untreasurer',
                      child: Text('총무 해제'),
                    ),
                  if (myRole?.canTransferOwnership == true)
                    const PopupMenuItem(
                      value: 'transfer',
                      child: Text('여행장 이전 요청'),
                    ),
                  const PopupMenuItem(
                    value: 'kick',
                    child: Text(
                      '강제 퇴장',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}
