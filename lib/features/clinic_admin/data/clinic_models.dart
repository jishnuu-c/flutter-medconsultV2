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
      clinicId: json['clinicId']?.toString() ??
          json['clinic_id']?.toString() ??
          json['id']?.toString() ??
          '',
      nameEn: json['nameEn']?.toString() ?? json['name_en']?.toString() ?? '',
      nameAr: json['nameAr']?.toString() ?? json['name_ar']?.toString() ?? '',
      descriptionEn: json['descriptionEn']?.toString() ??
          json['description_en']?.toString(),
      descriptionAr: json['descriptionAr']?.toString() ??
          json['description_ar']?.toString(),
      logoUrl: json['logoUrl']?.toString() ?? json['logo_url']?.toString(),
      website: json['website']?.toString(),
      email: json['email']?.toString(),
      phonePrimary: json['phonePrimary']?.toString() ??
          json['phone_primary']?.toString() ??
          json['phone']?.toString() ??
          '',
      phoneSecondary: json['phoneSecondary']?.toString() ??
          json['phone_secondary']?.toString(),
      mohLicenseNumber: json['mohLicenseNumber']?.toString() ??
          json['moh_license_number']?.toString() ??
          '',
      vatNumber:
          json['vatNumber']?.toString() ?? json['vat_number']?.toString(),
      mohVerified: json['mohVerified'] == true ||
          json['moh_verified'] == true ||
          json['mohVerified'] == 1 ||
          json['moh_verified'] == 1 ||
          json['mohVerified'] == 'true',
      mohVerifiedAt: json['mohVerifiedAt']?.toString() ??
          json['moh_verified_at']?.toString(),
      naphiesFacilityId: json['naphiesFacilityId']?.toString() ??
          json['naphies_facility_id']?.toString(),
      isActive: (json['isActive'] == null && json['is_active'] == null)
          ? true
          : (json['isActive'] == true ||
              json['is_active'] == true ||
              json['isActive'] == 1 ||
              json['is_active'] == 1 ||
              json['isActive'] == 'true'),
      overallRating: double.tryParse(json['overallRating']?.toString() ??
              json['overall_rating']?.toString() ??
              '') ??
          5.0,
      reviewCount: int.tryParse(json['reviewCount']?.toString() ??
              json['review_count']?.toString() ??
              '') ??
          0,
      createdAt:
          json['createdAt']?.toString() ?? json['created_at']?.toString(),
      updatedAt:
          json['updatedAt']?.toString() ?? json['updated_at']?.toString(),
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
      branchId: json['branchId']?.toString() ??
          json['branch_id']?.toString() ??
          json['id']?.toString() ??
          '',
      clinicId: json['clinicId']?.toString() ??
          json['clinic_id']?.toString() ??
          '',
      branchNameEn: json['branchNameEn']?.toString() ??
          json['branch_name_en']?.toString() ??
          json['nameEn']?.toString() ??
          '',
      branchNameAr: json['branchNameAr']?.toString() ??
          json['branch_name_ar']?.toString() ??
          json['nameAr']?.toString() ??
          '',
      cityId: json['cityId']?.toString() ??
          json['city_id']?.toString() ??
          '',
      localityId: json['localityId']?.toString() ??
          json['locality_id']?.toString(),
      addressLine1: json['addressLine1']?.toString() ??
          json['address_line1']?.toString() ??
          json['address']?.toString() ??
          '',
      addressLine2: json['addressLine2']?.toString() ??
          json['address_line2']?.toString(),
      latitude: double.tryParse(json['latitude']?.toString() ??
          json['lat']?.toString() ??
          ''),
      longitude: double.tryParse(json['longitude']?.toString() ??
          json['lng']?.toString() ??
          json['lon']?.toString() ??
          ''),
      phone: json['phone']?.toString() ?? json['phonePrimary']?.toString(),
      email: json['email']?.toString(),
      isPrimary: json['isPrimary'] == true ||
          json['is_primary'] == true ||
          json['isPrimary'] == 1 ||
          json['is_primary'] == 1,
      isActive: (json['isActive'] == null && json['is_active'] == null)
          ? true
          : (json['isActive'] == true ||
              json['is_active'] == true ||
              json['isActive'] == 1 ||
              json['is_active'] == 1),
      createdAt: json['createdAt']?.toString() ??
          json['created_at']?.toString(),
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
      hoursId: json['hoursId']?.toString() ?? json['hours_id']?.toString(),
      branchId: json['branchId']?.toString() ??
          json['branch_id']?.toString() ??
          '',
      dayOfWeek: int.tryParse(json['dayOfWeek']?.toString() ??
              json['day_of_week']?.toString() ??
              '') ??
          1,
      isClosed: json['isClosed'] == true ||
          json['is_closed'] == true ||
          json['isClosed'] == 1 ||
          json['is_closed'] == 1,
      openTime: json['openTime']?.toString() ??
          json['open_time']?.toString() ??
          '09:00',
      closeTime: json['closeTime']?.toString() ??
          json['close_time']?.toString() ??
          '17:00',
      breakStart: json['breakStart']?.toString() ??
          json['break_start']?.toString(),
      breakEnd: json['breakEnd']?.toString() ??
          json['break_end']?.toString(),
      notes: json['notes']?.toString(),
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
      clinicId: json['clinicId']?.toString() ??
          json['clinic_id']?.toString() ??
          '',
      specialtyId: json['specialtyId']?.toString() ??
          json['specialty_id']?.toString() ??
          '',
      createdAt: json['createdAt']?.toString() ??
          json['created_at']?.toString(),
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
      clinicId: json['clinicId']?.toString() ??
          json['clinic_id']?.toString() ??
          '',
      languageId: json['languageId']?.toString() ??
          json['language_id']?.toString() ??
          '',
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
      clinicId: json['clinicId']?.toString() ??
          json['clinic_id']?.toString() ??
          '',
      providerId: json['providerId']?.toString() ??
          json['provider_id']?.toString() ??
          '',
      networkClass: json['networkClass']?.toString() ??
          json['network_class']?.toString() ??
          '',
      isActive: (json['isActive'] == null && json['is_active'] == null)
          ? true
          : (json['isActive'] == true ||
              json['is_active'] == true ||
              json['isActive'] == 1 ||
              json['is_active'] == 1),
      createdAt: json['createdAt']?.toString() ??
          json['created_at']?.toString(),
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
