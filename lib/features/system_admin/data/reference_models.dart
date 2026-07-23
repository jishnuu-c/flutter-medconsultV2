class CityModel {
  final String cityId;
  final String countryCode;
  final String nameEn;
  final String nameAr;
  final bool isActive;
  final int sortOrder;
  final String? createdAt;

  CityModel({
    required this.cityId,
    required this.countryCode,
    required this.nameEn,
    required this.nameAr,
    required this.isActive,
    required this.sortOrder,
    this.createdAt,
  });

  factory CityModel.fromJson(Map<String, dynamic> json) {
    return CityModel(
      cityId: json['cityId']?.toString() ?? '',
      countryCode: json['countryCode'] ?? 'SA',
      nameEn: json['nameEn'] ?? '',
      nameAr: json['nameAr'] ?? '',
      isActive: json['isActive'] ?? true,
      sortOrder: json['sortOrder'] ?? 1,
      createdAt: json['createdAt'],
    );
  }

  Map<String, dynamic> toJson() => {
        'countryCode': countryCode,
        'nameEn': nameEn,
        'nameAr': nameAr,
        'isActive': isActive,
        'sortOrder': sortOrder,
      };
}

class LocalityModel {
  final String localityId;
  final String cityId;
  final String nameEn;
  final String nameAr;
  final String? postalCode;
  final double? latitude;
  final double? longitude;
  final bool isActive;
  final String? createdAt;

  LocalityModel({
    required this.localityId,
    required this.cityId,
    required this.nameEn,
    required this.nameAr,
    this.postalCode,
    this.latitude,
    this.longitude,
    required this.isActive,
    this.createdAt,
  });

  factory LocalityModel.fromJson(Map<String, dynamic> json) {
    return LocalityModel(
      localityId: json['localityId']?.toString() ?? '',
      cityId: json['cityId']?.toString() ?? '',
      nameEn: json['nameEn'] ?? '',
      nameAr: json['nameAr'] ?? '',
      postalCode: json['postalCode'],
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'],
    );
  }

  Map<String, dynamic> toJson() => {
        'cityId': cityId,
        'nameEn': nameEn,
        'nameAr': nameAr,
        if (postalCode != null) 'postalCode': postalCode,
        'isActive': isActive,
      };
}

class SpecialtyModel {
  final String specialtyId;
  final String code;
  final String nameEn;
  final String nameAr;
  final String category;
  final String? iconSlug;
  final bool isActive;
  final int sortOrder;
  final String? createdAt;

  SpecialtyModel({
    required this.specialtyId,
    required this.code,
    required this.nameEn,
    required this.nameAr,
    required this.category,
    this.iconSlug,
    required this.isActive,
    required this.sortOrder,
    this.createdAt,
  });

  factory SpecialtyModel.fromJson(Map<String, dynamic> json) {
    return SpecialtyModel(
      specialtyId: json['specialtyId']?.toString() ?? '',
      code: json['code'] ?? '',
      nameEn: json['nameEn'] ?? '',
      nameAr: json['nameAr'] ?? '',
      category: json['category'] ?? 'GENERAL',
      iconSlug: json['iconSlug'],
      isActive: json['isActive'] ?? true,
      sortOrder: json['sortOrder'] ?? 1,
      createdAt: json['createdAt'],
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'nameEn': nameEn,
        'nameAr': nameAr,
        'category': category,
        'isActive': isActive,
      };
}

class SubSpecialtyModel {
  final String subSpecialtyId;
  final String specialtyId;
  final String nameEn;
  final String nameAr;
  final bool isActive;
  final String? createdAt;

  SubSpecialtyModel({
    required this.subSpecialtyId,
    required this.specialtyId,
    required this.nameEn,
    required this.nameAr,
    required this.isActive,
    this.createdAt,
  });

  factory SubSpecialtyModel.fromJson(Map<String, dynamic> json) {
    return SubSpecialtyModel(
      subSpecialtyId: json['subSpecialtyId']?.toString() ?? '',
      specialtyId: json['specialtyId']?.toString() ?? '',
      nameEn: json['nameEn'] ?? '',
      nameAr: json['nameAr'] ?? '',
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'],
    );
  }

  Map<String, dynamic> toJson() => {
        'specialtyId': specialtyId,
        'nameEn': nameEn,
        'nameAr': nameAr,
        'isActive': isActive,
      };
}

class LanguageModel {
  final String languageId;
  final String code;
  final String nameEn;
  final String nameAr;
  final bool isActive;

  LanguageModel({
    required this.languageId,
    required this.code,
    required this.nameEn,
    required this.nameAr,
    required this.isActive,
  });

  factory LanguageModel.fromJson(Map<String, dynamic> json) {
    return LanguageModel(
      languageId: json['languageId']?.toString() ?? '',
      code: json['code'] ?? '',
      nameEn: json['nameEn'] ?? '',
      nameAr: json['nameAr'] ?? '',
      isActive: json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'nameEn': nameEn,
        'nameAr': nameAr,
        'isActive': isActive,
      };
}

class InsuranceProviderModel {
  final String providerId;
  final String nameEn;
  final String nameAr;
  final String? logoUrl;
  final bool isActive;
  final String? createdAt;

  InsuranceProviderModel({
    required this.providerId,
    required this.nameEn,
    required this.nameAr,
    this.logoUrl,
    required this.isActive,
    this.createdAt,
  });

  factory InsuranceProviderModel.fromJson(Map<String, dynamic> json) {
    return InsuranceProviderModel(
      providerId: json['providerId']?.toString() ?? '',
      nameEn: json['nameEn'] ?? '',
      nameAr: json['nameAr'] ?? '',
      logoUrl: json['logoUrl'],
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'],
    );
  }

  Map<String, dynamic> toJson() => {
        'nameEn': nameEn,
        'nameAr': nameAr,
        'isActive': isActive,
      };
}
