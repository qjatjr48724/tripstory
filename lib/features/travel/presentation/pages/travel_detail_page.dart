import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/roles.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/travel_member.dart';
import '../providers/travel_providers.dart';

class TravelDetailPage extends ConsumerWidget {
  const TravelDetailPage({super.key, required this.travelId});

  final String travelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTravel = ref.watch(travelDetailProvider(travelId));
    final dateFormat = DateFormat('yyyy.MM.dd');

    // 상세 membership을 목록 캐시에 동기화 (승인 후 '승인 대기' 뱃지 제거)
    ref.listen(travelDetailProvider(travelId), (prev, next) {
      next.whenData((_) => ref.invalidate(myTravelsProvider));
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('여행'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ref.invalidate(myTravelsProvider);
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.travels);
            }
          },
        ),
      ),
      body: asyncTravel.when(
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
                  onPressed: () =>
                      ref.invalidate(travelDetailProvider(travelId)),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
        data: (travel) {
          final isPending = travel.myMemberStatus == MemberStatus.pending;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(travelDetailProvider(travelId));
              await ref.read(travelDetailProvider(travelId).future);
            },
            child: ListView(
              padding: const EdgeInsets.all(24),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            travel.name,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${dateFormat.format(travel.startDate)} ~ '
                            '${dateFormat.format(travel.endDate)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            travel.region,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  color: AppColors.primary,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (!isPending &&
                        travel.myRole?.canViewInviteCode == true &&
                        travel.inviteCode != null)
                      _InviteCodeChip(code: travel.inviteCode!),
                  ],
                ),
                if (travel.myRole != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(
                      label: Text(
                        isPending ? '승인 대기' : travel.myRole!.label,
                      ),
                      backgroundColor: AppColors.surfaceMuted,
                      side: BorderSide.none,
                    ),
                  ),
                ],
                if (travel.memo != null && travel.memo!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(travel.memo!),
                ],
                if (isPending) ...[
                  const SizedBox(height: 28),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.hourglass_top_outlined, size: 36),
                        const SizedBox(height: 12),
                        Text(
                          '여행장의 참가 승인을 기다리는 중이에요',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '승인되면 장소·구성원 메뉴를 이용할 수 있습니다.',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () {
                            ref.invalidate(travelDetailProvider(travelId));
                            ref.invalidate(myTravelsProvider);
                          },
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('승인 여부 확인'),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 28),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.group_outlined),
                    title: const Text('구성원 관리'),
                    subtitle: const Text('역할 · 총무 · 퇴장 · 여행장 이전'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go(
                      '${AppRoutes.travels}/${travel.id}/members',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.place_outlined),
                    title: const Text('장소 후보'),
                    subtitle: const Text('가고 싶은 장소 저장 · 지도 보기'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go(
                      '${AppRoutes.travels}/${travel.id}/places',
                    ),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    '일정 · 비용 등은 다음 단계에서 추가됩니다.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InviteCodeChip extends StatelessWidget {
  const _InviteCodeChip({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('초대코드를 복사했어요')),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '초대코드',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  Text(
                    code,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                  ),
                ],
              ),
              const Icon(Icons.copy, size: 16),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
