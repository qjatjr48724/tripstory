import 'travel_member.dart';

class TravelPhoto {
  const TravelPhoto({
    required this.id,
    required this.travelId,
    required this.storagePath,
    required this.createdAt,
    this.title,
    this.memo,
    this.uploadedByMemberId,
    this.uploader,
  });

  final String id;
  final String travelId;
  final String storagePath;
  final String? title;
  final String? memo;
  final String? uploadedByMemberId;
  final TravelMember? uploader;
  final DateTime createdAt;

  factory TravelPhoto.fromJson(
    Map<String, dynamic> json, {
    Map<String, TravelMember>? membersById,
  }) {
    final uploaderId = json['uploaded_by_member_id'] as String?;
    return TravelPhoto(
      id: json['id'] as String,
      travelId: json['travel_id'] as String,
      storagePath: json['storage_path'] as String,
      title: json['title'] as String?,
      memo: json['memo'] as String?,
      uploadedByMemberId: uploaderId,
      uploader: uploaderId == null ? null : membersById?[uploaderId],
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
