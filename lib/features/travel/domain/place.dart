class Place {
  const Place({
    required this.id,
    required this.travelId,
    required this.createdByMemberId,
    required this.name,
    required this.version,
    this.address,
    this.countryCode,
    this.latitude,
    this.longitude,
    this.memo,
    this.googlePlaceId,
    this.mapsUrl,
    this.creatorDisplayName,
    this.creatorColorHex,
  });

  final String id;
  final String travelId;
  final String createdByMemberId;
  final String name;
  final String? address;
  final String? countryCode;
  final double? latitude;
  final double? longitude;
  final String? memo;
  final String? googlePlaceId;
  final String? mapsUrl;
  final int version;
  final String? creatorDisplayName;
  final String? creatorColorHex;

  bool get isKorea =>
      (countryCode ?? '').toUpperCase() == 'KR' ||
      (countryCode ?? '').toUpperCase() == 'KOR';

  bool get hasCoordinates => latitude != null && longitude != null;

  bool get canOpenMap =>
      (mapsUrl != null && mapsUrl!.isNotEmpty) ||
      (googlePlaceId != null && googlePlaceId!.isNotEmpty) ||
      hasCoordinates;

  factory Place.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? member;
    final rawMember = json['travel_members'];
    if (rawMember is Map) {
      member = Map<String, dynamic>.from(rawMember);
    }

    return Place(
      id: json['id'] as String,
      travelId: json['travel_id'] as String,
      createdByMemberId: json['created_by_member_id'] as String,
      name: json['name'] as String,
      address: json['address'] as String?,
      countryCode: json['country_code'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      memo: json['memo'] as String?,
      googlePlaceId: json['google_place_id'] as String?,
      mapsUrl: json['maps_url'] as String?,
      version: json['version'] as int? ?? 1,
      creatorDisplayName: member?['display_name_snapshot'] as String?,
      creatorColorHex: member?['color_hex'] as String?,
    );
  }
}
