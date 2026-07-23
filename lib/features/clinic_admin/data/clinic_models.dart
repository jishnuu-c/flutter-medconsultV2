class ClinicModel {
  final String clinicId;
  final String nameEn;
  final String nameAr;
  final String? descriptionEn;
  final String? descriptionAr;
  final String? logoUrl;
  final String? website;
  final String? email;
  final String phonePrimary;
  final String? phoneSecondary;
  final String mohLicenseNumber;
  final String? vatNumber;
  final bool mohVerified;
  final String? mohVerifiedAt;
  final String? naphiesFacilityId;
  final bool isActive;
  final double overallRating;
  final int reviewCount;
  final String? createdAt;
  final String? updatedAt;

  ClinicModel({
    required this.clinicId,
    required this.nameEn,
    required this.nameAr,
    this.descriptionEn,
    this.descriptionAr,
    this.logoUrl,
    this.website,
    this.email,
    required this.phonePrimary,
    this.phoneSecondary,
    required this.mohLicenseNumber,
    this.vatNumber,
    this.mohVerified = false,
    this.mohVerifiedAt,
    this.naphiesFacilityId,
    required this.isActive,
    this.overallRating = 5.0,
    this.reviewCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory ClinicModel.fromJson(Map<String, dynamic> json) {
    return ClinicModel(
      clinicId: json['clinicId']?.toString() ?? '',
      nameEn: json['nameEn'] ?? '',
      nameAr: json['nameAr'] ?? '',
      descriptionEn: json['descriptionEn'],
      descriptionAr: json['descriptionAr'],
      logoUrl: json['logoUrl'],
      website: json['website'],
      email: json['email'],
      phonePrimary: json['phonePrimary'] ?? '',
      phoneSecondary: json['phoneSecondary'],
      mohLicenseNumber: json['mohLicenseNumber'] ?? '',
      vatNumber: json['vatNumber'],
      mohVerified: json['mohVerified'] ?? false,
      mohVerifiedAt: json['mohVerifiedAt'],
      naphiesFacilityId: json['naphiesFacilityId'],
      isActive: json['isActive'] ?? true,
      overallRating: (json['overallRating'] as num?)?.toDouble() ?? 5.0,
      reviewCount: json['reviewCount'] ?? 0,
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
    );
  }

  Map<String, dynamic> toJson() => {
        'nameEn': nameEn,
        'nameAr': nameAr,
        if (descriptionEn != null) 'descriptionEn': descriptionEn,
        if (descriptionAr != null) 'descriptionAr': descriptionAr,
        if (website != null) 'website': website,
        if (email != null) 'email': email,
        'phonePrimary': phonePrimary,
        if (phoneSecondary != null) 'phoneSecondary': phoneSecondary,
        'mohLicenseNumber': mohLicenseNumber,
        if (vatNumber != null) 'vatNumber': vatNumber,
        'isActive': isActive,
      };
}

class ClinicBranchModel {
  final String branchId;
  final String clinicId;
  final String branchNameEn;
  final String branchNameAr;
  final String cityId;
  final String? localityId;
  final String addressLine1;
  final String? addressLine2;
  final double? latitude;
  final double? longitude;
  final String? phone;
  final String? email;
  final bool isPrimary;
  final bool isActive;
  final String? createdAt;

  ClinicBranchModel({
    required this.branchId,
    required this.clinicId,
    required this.branchNameEn,
    required this.branchNameAr,
    required this.cityId,
    this.localityId,
    required this.addressLine1,
    this.addressLine2,
    this.latitude,
    this.longitude,
    this.phone,
    this.email,
    required this.isPrimary,
    required this.isActive,
    this.createdAt,
  });

  factory ClinicBranchModel.fromJson(Map<String, dynamic> json) {
    return ClinicBranchModel(
      branchId: json['branchId']?.toString() ?? '',
      clinicId: json['clinicId']?.toString() ?? '',
      branchNameEn: json['branchNameEn'] ?? '',
      branchNameAr: json['branchNameAr'] ?? '',
      cityId: json['cityId']?.toString() ?? '',
      localityId: json['localityId']?.toString(),
      addressLine1: json['addressLine1'] ?? '',
      addressLine2: json['addressLine2'],
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      phone: json['phone'],
      email: json['email'],
      isPrimary: json['isPrimary'] ?? false,
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'],
    );
  }

  Map<String, dynamic> toJson() => {
        'branchNameEn': branchNameEn,
        'branchNameAr': branchNameAr,
        'cityId': cityId,
        if (localityId != null) 'localityId': localityId,
        'addressLine1': addressLine1,
        if (addressLine2 != null) 'addressLine2': addressLine2,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        'isPrimary': isPrimary,
        'isActive': isActive,
      };
}

class ClinicOperatingHourModel {
  final String? hoursId;
  final String branchId;
  final int dayOfWeek;
  final bool isClosed;
  final String openTime;
  final String closeTime;
  final String? breakStart;
  final String? breakEnd;
  final String? notes;

  ClinicOperatingHourModel({
    this.hoursId,
    required this.branchId,
    required this.dayOfWeek,
    required this.isClosed,
    required this.openTime,
    required this.closeTime,
    this.breakStart,
    this.breakEnd,
    this.notes,
  });

  factory ClinicOperatingHourModel.fromJson(Map<String, dynamic> json) {
    return ClinicOperatingHourModel(
      hoursId: json['hoursId']?.toString(),
      branchId: json['branchId']?.toString() ?? '',
      dayOfWeek: json['dayOfWeek'] ?? 1,
      isClosed: json['isClosed'] ?? false,
      openTime: json['openTime'] ?? '09:00',
      closeTime: json['closeTime'] ?? '17:00',
      breakStart: json['breakStart'],
      breakEnd: json['breakEnd'],
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() => {
        'branchId': branchId,
        'dayOfWeek': dayOfWeek,
        'isClosed': isClosed,
        'openTime': openTime,
        'closeTime': closeTime,
        if (breakStart != null) 'breakStart': breakStart,
        if (breakEnd != null) 'breakEnd': breakEnd,
        if (notes != null) 'notes': notes,
      };
}

class ClinicSpecialtyModel {
  final String id;
  final String clinicId;
  final String specialtyId;
  final String? createdAt;

  ClinicSpecialtyModel({
    required this.id,
    required this.clinicId,
    required this.specialtyId,
    this.createdAt,
  });

  factory ClinicSpecialtyModel.fromJson(Map<String, dynamic> json) {
    return ClinicSpecialtyModel(
      id: json['id']?.toString() ?? '',
      clinicId: json['clinicId']?.toString() ?? '',
      specialtyId: json['specialtyId']?.toString() ?? '',
      createdAt: json['createdAt'],
    );
  }
}

class ClinicLanguageModel {
  final String id;
  final String clinicId;
  final String languageId;

  ClinicLanguageModel({
    required this.id,
    required this.clinicId,
    required this.languageId,
  });

  factory ClinicLanguageModel.fromJson(Map<String, dynamic> json) {
    return ClinicLanguageModel(
      id: json['id']?.toString() ?? '',
      clinicId: json['clinicId']?.toString() ?? '',
      languageId: json['languageId']?.toString() ?? '',
    );
  }
}

class ClinicInsuranceModel {
  final String id;
  final String clinicId;
  final String providerId;
  final String networkClass;
  final bool isActive;
  final String? createdAt;

  ClinicInsuranceModel({
    required this.id,
    required this.clinicId,
    required this.providerId,
    required this.networkClass,
    required this.isActive,
    this.createdAt,
  });

  factory ClinicInsuranceModel.fromJson(Map<String, dynamic> json) {
    return ClinicInsuranceModel(
      id: json['id']?.toString() ?? '',
      clinicId: json['clinicId']?.toString() ?? '',
      providerId: json['providerId']?.toString() ?? '',
      networkClass: json['networkClass'] ?? '',
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'],
    );
  }

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'networkClass': networkClass,
        'isActive': isActive,
      };
}

class ClinicDetailResponse extends ClinicModel {
  final List<ClinicBranchModel> branches;
  final List<ClinicSpecialtyModel> specialties;
  final List<ClinicInsuranceModel> insurances;
  final List<ClinicLanguageModel> languages;

  ClinicDetailResponse({
    required super.clinicId,
    required super.nameEn,
    required super.nameAr,
    super.descriptionEn,
    super.descriptionAr,
    super.logoUrl,
    super.website,
    super.email,
    required super.phonePrimary,
    super.phoneSecondary,
    required super.mohLicenseNumber,
    super.vatNumber,
    super.mohVerified,
    super.mohVerifiedAt,
    super.naphiesFacilityId,
    required super.isActive,
    super.overallRating,
    super.reviewCount,
    super.createdAt,
    super.updatedAt,
    required this.branches,
    required this.specialties,
    required this.insurances,
    required this.languages,
  });

  factory ClinicDetailResponse.fromJson(Map<String, dynamic> json) {
    final base = ClinicModel.fromJson(json);
    return ClinicDetailResponse(
      clinicId: base.clinicId,
      nameEn: base.nameEn,
      nameAr: base.nameAr,
      descriptionEn: base.descriptionEn,
      descriptionAr: base.descriptionAr,
      logoUrl: base.logoUrl,
      website: base.website,
      email: base.email,
      phonePrimary: base.phonePrimary,
      phoneSecondary: base.phoneSecondary,
      mohLicenseNumber: base.mohLicenseNumber,
      vatNumber: base.vatNumber,
      mohVerified: base.mohVerified,
      mohVerifiedAt: base.mohVerifiedAt,
      naphiesFacilityId: base.naphiesFacilityId,
      isActive: base.isActive,
      overallRating: base.overallRating,
      reviewCount: base.reviewCount,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
      branches: (json['branches'] as List? ?? []).map((e) => ClinicBranchModel.fromJson(e)).toList(),
      specialties: (json['specialties'] as List? ?? []).map((e) => ClinicSpecialtyModel.fromJson(e)).toList(),
      insurances: (json['insurances'] as List? ?? []).map((e) => ClinicInsuranceModel.fromJson(e)).toList(),
      languages: (json['languages'] as List? ?? []).map((e) => ClinicLanguageModel.fromJson(e)).toList(),
    );
  }
}
