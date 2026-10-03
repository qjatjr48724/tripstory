import 'place.dart';

class SchedulePlanB {
  const SchedulePlanB({
    required this.id,
    required this.scheduleId,
    required this.placeId,
    required this.slot,
    this.place,
  });

  final String id;
  final String scheduleId;
  final String placeId;
  final int slot;
  final Place? place;

  factory SchedulePlanB.fromJson(Map<String, dynamic> json) {
    Place? place;
    final rawPlace = json['places'];
    if (rawPlace is Map) {
      place = Place.fromJson(Map<String, dynamic>.from(rawPlace));
    }

    return SchedulePlanB(
      id: json['id'] as String,
      scheduleId: json['schedule_id'] as String,
      placeId: json['place_id'] as String,
      slot: json['slot'] as int,
      place: place,
    );
  }
}

class ScheduleItem {
  const ScheduleItem({
    required this.id,
    required this.travelId,
    required this.scheduleDate,
    required this.sortOrder,
    required this.title,
    required this.isVisited,
    required this.version,
    this.placeId,
    this.startTime,
    this.memo,
    this.place,
    this.planB = const [],
  });

  final String id;
  final String travelId;
  final DateTime scheduleDate;
  final String? placeId;
  final Duration? startTime;
  final int sortOrder;
  final String title;
  final String? memo;
  final bool isVisited;
  final int version;
  final Place? place;
  final List<SchedulePlanB> planB;

  SchedulePlanB? planBAt(int slot) {
    for (final p in planB) {
      if (p.slot == slot) return p;
    }
    return null;
  }

  String? get startTimeLabel {
    final t = startTime;
    if (t == null) return null;
    final h = t.inHours.toString().padLeft(2, '0');
    final m = (t.inMinutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    Place? place;
    final rawPlace = json['places'];
    if (rawPlace is Map) {
      place = Place.fromJson(Map<String, dynamic>.from(rawPlace));
    }

    final planBRaw = json['plan_b'];
    final planB = <SchedulePlanB>[];
    if (planBRaw is List) {
      for (final row in planBRaw) {
        if (row is Map) {
          planB.add(SchedulePlanB.fromJson(Map<String, dynamic>.from(row)));
        }
      }
      planB.sort((a, b) => a.slot.compareTo(b.slot));
    }

    return ScheduleItem(
      id: json['id'] as String,
      travelId: json['travel_id'] as String,
      placeId: json['place_id'] as String?,
      scheduleDate: DateTime.parse(json['schedule_date'] as String),
      startTime: _parseTime(json['start_time'] as String?),
      sortOrder: json['sort_order'] as int? ?? 0,
      title: json['title'] as String,
      memo: json['memo'] as String?,
      isVisited: json['is_visited'] as bool? ?? false,
      version: json['version'] as int? ?? 1,
      place: place,
      planB: planB,
    );
  }

  static Duration? _parseTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final s = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;
    return Duration(hours: h, minutes: m, seconds: s);
  }

  static String? formatTimeForDb(Duration? time) {
    if (time == null) return null;
    final h = time.inHours.toString().padLeft(2, '0');
    final m = (time.inMinutes % 60).toString().padLeft(2, '0');
    final s = (time.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
