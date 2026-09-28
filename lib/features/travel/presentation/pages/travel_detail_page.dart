import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/roles.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/travel_providers.dart';

class TravelDetailPage extends ConsumerWidget {
  const TravelDetailPage({super.key, required this.travelId});

  final String travelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTravel = ref.watch(travelDetailProvider(travelId));
    final dateFormat = DateFormat('yyyy.MM.dd');

    return Scaffold(
      appBar: AppBar(
        title: const Text('여행'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.travels),
        ),
      ),
      body: asyncTravel.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('$e', textAlign: TextAlign.center),
          ),
        ),
        data: (travel) {
          return ListView(
            padding: const EdgeInsets.all(24),
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
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.primary,
                    ),
              ),
              if (travel.myRole != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    label: Text(travel.myRole!.label),
                    backgroundColor: AppColors.surfaceMuted,
                    side: BorderSide.none,
                  ),
                ),
              ],
              if (travel.memo != null && travel.memo!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(travel.memo!),
              ],
              const SizedBox(height: 28),
              if (travel.inviteCode != null) ...[
                Text(
                  '초대코드',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          travel.inviteCode!,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                letterSpacing: 2,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: '복사',
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: travel.inviteCode!),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('초대코드를 복사했어요')),
                          );
                        },
                        icon: const Icon(Icons.copy),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '친구에게 이 코드를 공유하면 여행에 참여할 수 있어요.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 40),
              Text(
                '일정 · 장소 · 비용 등은 다음 단계에서 추가됩니다.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}
