import 'expense.dart';
import 'travel_member.dart';

enum ReservationType {
  transport,
  lodging,
  other;

  static ReservationType fromDb(String value) => switch (value) {
        'transport' => ReservationType.transport,
        'lodging' => ReservationType.lodging,
        _ => ReservationType.other,
      };

  String get dbValue => switch (this) {
        ReservationType.transport => 'transport',
        ReservationType.lodging => 'lodging',
        ReservationType.other => 'other',
      };

  String get label => switch (this) {
        ReservationType.transport => '교통',
        ReservationType.lodging => '숙소',
        ReservationType.other => '기타',
      };
}

class ReservationImage {
  const ReservationImage({
    required this.id,
    required this.reservationId,
    required this.storagePath,
    this.createdByMemberId,
  });

  final String id;
  final String reservationId;
  final String storagePath;
  final String? createdByMemberId;

  factory ReservationImage.fromJson(Map<String, dynamic> json) {
    return ReservationImage(
      id: json['id'] as String,
      reservationId: json['reservation_id'] as String,
      storagePath: json['storage_path'] as String,
      createdByMemberId: json['created_by_member_id'] as String?,
    );
  }
}

class Reservation {
  const Reservation({
    required this.id,
    required this.travelId,
    required this.type,
    required this.title,
    required this.version,
    this.bookerMemberId,
    this.booker,
    this.confirmationNumber,
    this.costAmount,
    this.costCurrency,
    this.startsAt,
    this.confirmationUrl,
    this.memo,
    this.lodgingAddress,
    this.lodgingRoomInfo,
    this.linkedExpenseId,
    this.images = const [],
  });

  final String id;
  final String travelId;
  final ReservationType type;
  final String title;
  final String? bookerMemberId;
  final TravelMember? booker;
  final String? confirmationNumber;
  final int? costAmount;
  final String? costCurrency;
  final DateTime? startsAt;
  final String? confirmationUrl;
  final String? memo;
  final String? lodgingAddress;
  final String? lodgingRoomInfo;
  final String? linkedExpenseId;
  final int version;
  final List<ReservationImage> images;

  factory Reservation.fromJson(
    Map<String, dynamic> json, {
    Map<String, TravelMember>? membersById,
  }) {
    final bookerId = json['booker_member_id'] as String?;
    final imagesRaw = json['reservation_images'];
    final images = <ReservationImage>[];
    if (imagesRaw is List) {
      for (final row in imagesRaw) {
        if (row is Map) {
          images.add(ReservationImage.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }

    return Reservation(
      id: json['id'] as String,
      travelId: json['travel_id'] as String,
      type: ReservationType.fromDb(json['type'] as String? ?? 'other'),
      title: json['title'] as String? ?? '',
      bookerMemberId: bookerId,
      booker: bookerId == null ? null : membersById?[bookerId],
      confirmationNumber: json['confirmation_number'] as String?,
      costAmount: json['cost_amount'] as int?,
      costCurrency: json['cost_currency'] as String?,
      startsAt: json['starts_at'] != null
          ? DateTime.parse(json['starts_at'] as String)
          : null,
      confirmationUrl: json['confirmation_url'] as String?,
      memo: json['memo'] as String?,
      lodgingAddress: json['lodging_address'] as String?,
      lodgingRoomInfo: json['lodging_room_info'] as String?,
      linkedExpenseId: json['linked_expense_id'] as String?,
      version: json['version'] as int? ?? 1,
      images: images,
    );
  }

  ExpenseCategory get expenseCategory => switch (type) {
        ReservationType.transport => ExpenseCategory.transport,
        ReservationType.lodging => ExpenseCategory.lodging,
        ReservationType.other => ExpenseCategory.other,
      };
}
