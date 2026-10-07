import 'travel_member.dart';

class TravelLink {
  const TravelLink({
    required this.id,
    required this.travelId,
    required this.title,
    required this.url,
    required this.version,
    this.memo,
    this.createdByMemberId,
    this.createdBy,
  });

  final String id;
  final String travelId;
  final String title;
  final String url;
  final String? memo;
  final String? createdByMemberId;
  final TravelMember? createdBy;
  final int version;

  factory TravelLink.fromJson(
    Map<String, dynamic> json, {
    Map<String, TravelMember>? membersById,
  }) {
    final creatorId = json['created_by_member_id'] as String?;
    return TravelLink(
      id: json['id'] as String,
      travelId: json['travel_id'] as String,
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      memo: json['memo'] as String?,
      createdByMemberId: creatorId,
      createdBy: creatorId == null ? null : membersById?[creatorId],
      version: json['version'] as int? ?? 1,
    );
  }
}
