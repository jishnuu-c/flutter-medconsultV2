enum DoctorTitle {
  DR('DR'),
  PROF('PROF'),
  ASSOC_PROF('ASSOC_PROF');

  final String value;
  const DoctorTitle(this.value);

  static DoctorTitle fromString(String val) {
    return DoctorTitle.values.firstWhere(
      (e) => e.value == val,
      orElse: () => DoctorTitle.DR,
    );
  }
}

enum SessionType {
  IN_CLINIC('IN_CLINIC'),
  VIRTUAL('VIRTUAL'),
  BOTH('BOTH');

  final String value;
  const SessionType(this.value);

  static SessionType fromString(String val) {
    return SessionType.values.firstWhere(
      (e) => e.value == val,
      orElse: () => SessionType.IN_CLINIC,
    );
  }
}

enum SlotStatus {
  AVAILABLE('AVAILABLE'),
  BOOKED('BOOKED'),
  BLOCKED('BLOCKED'),
  NO_SHOW('NO_SHOW');

  final String value;
  const SlotStatus(this.value);

  static SlotStatus fromString(String val) {
    return SlotStatus.values.firstWhere(
      (e) => e.value == val,
      orElse: () => SlotStatus.AVAILABLE,
    );
  }
}

enum LanguageProficiency {
  NATIVE('NATIVE'),
  FLUENT('FLUENT'),
  INTERMEDIATE('INTERMEDIATE'),
  BASIC('BASIC');

  final String value;
  const LanguageProficiency(this.value);

  static LanguageProficiency fromString(String val) {
    return LanguageProficiency.values.firstWhere(
      (e) => e.value == val,
      orElse: () => LanguageProficiency.FLUENT,
    );
  }
}

enum LeaveType {
  ANNUAL('ANNUAL'),
  SICK('SICK'),
  EMERGENCY('EMERGENCY'),
  CONFERENCE('CONFERENCE');

  final String value;
  const LeaveType(this.value);

  static LeaveType fromString(String val) {
    return LeaveType.values.firstWhere(
      (e) => e.value == val,
      orElse: () => LeaveType.ANNUAL,
    );
  }
}

class DoctorModel {
  final String doctorId;
  final String userId;
  final String fullName;
  final String mohRegistrationNumber;
  final bool mohVerified;
  final DoctorTitle title;
  final String? bioEn;
  final String? bioAr;
  final int experienceYears;
  final double overallRating;
  final int reviewCount;
  final double consultationFeeSar;
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;

  DoctorModel({
    required this.doctorId,
    required this.userId,
    required this.fullName,
    required this.mohRegistrationNumber,
    required this.mohVerified,
    required this.title,
    this.bioEn,
    this.bioAr,
    required this.experienceYears,
    required this.overallRating,
    required this.reviewCount,
    required this.consultationFeeSar,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  factory DoctorModel.fromJson(Map<String, dynamic> json) {
    return DoctorModel(
      doctorId: json['doctorId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      fullName: json['fullName'] ?? json['name'] ?? '',
      mohRegistrationNumber: json['mohRegistrationNumber'] ?? '',
      mohVerified: json['mohVerified'] ?? false,
      title: DoctorTitle.fromString(json['title'] ?? 'DR'),
      bioEn: json['bioEn'],
      bioAr: json['bioAr'],
      experienceYears: json['experienceYears'] ?? 5,
      overallRating: (json['overallRating'] as num?)?.toDouble() ?? 5.0,
      reviewCount: json['reviewCount'] ?? 0,
      consultationFeeSar: (json['consultationFeeSar'] as num?)?.toDouble() ?? 150.0,
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'mohRegistrationNumber': mohRegistrationNumber,
        'mohVerified': mohVerified,
        'title': title.value,
        if (bioEn != null) 'bioEn': bioEn,
        if (bioAr != null) 'bioAr': bioAr,
        'experienceYears': experienceYears,
        'consultationFeeSar': consultationFeeSar,
        'isActive': isActive,
      };
}

class DoctorClinicModel {
  final String dcId;
  final String doctorId;
  final String clinicId;
  final String branchId;
  final String department;
  final double consultationFeeSar;
  final bool isPrimary;
  final String startDate;
  final String? endDate;
  final bool isActive;
  final String? clinicNameEn;
  final String? branchNameEn;

  DoctorClinicModel({
    required this.dcId,
    required this.doctorId,
    required this.clinicId,
    required this.branchId,
    required this.department,
    required this.consultationFeeSar,
    required this.isPrimary,
    required this.startDate,
    this.endDate,
    required this.isActive,
    this.clinicNameEn,
    this.branchNameEn,
  });

  factory DoctorClinicModel.fromJson(Map<String, dynamic> json) {
    return DoctorClinicModel(
      dcId: json['dcId']?.toString() ?? '',
      doctorId: json['doctorId']?.toString() ?? '',
      clinicId: json['clinicId']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? '',
      department: json['department'] ?? 'General Practice',
      consultationFeeSar: (json['consultationFeeSar'] as num?)?.toDouble() ?? 150.0,
      isPrimary: json['isPrimary'] ?? true,
      startDate: json['startDate'] ?? DateTime.now().toString().split(' ')[0],
      endDate: json['endDate'],
      isActive: json['isActive'] ?? true,
      clinicNameEn: json['clinicNameEn'],
      branchNameEn: json['branchNameEn'],
    );
  }

  Map<String, dynamic> toJson() => {
        'doctorId': doctorId,
        'clinicId': clinicId,
        'branchId': branchId,
        'department': department,
        'consultationFeeSar': consultationFeeSar,
        'isPrimary': isPrimary,
        'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
        'isActive': isActive,
      };
}

class DoctorSpecialtyModel {
  final String id;
  final String doctorId;
  final String specialtyId;
  final String? subSpecialtyId;
  final bool isPrimary;

  DoctorSpecialtyModel({
    required this.id,
    required this.doctorId,
    required this.specialtyId,
    this.subSpecialtyId,
    required this.isPrimary,
  });

  factory DoctorSpecialtyModel.fromJson(Map<String, dynamic> json) {
    return DoctorSpecialtyModel(
      id: json['id']?.toString() ?? '',
      doctorId: json['doctorId']?.toString() ?? '',
      specialtyId: json['specialtyId']?.toString() ?? '',
      subSpecialtyId: json['subSpecialtyId']?.toString(),
      isPrimary: json['isPrimary'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'doctorId': doctorId,
        'specialtyId': specialtyId,
        if (subSpecialtyId != null) 'subSpecialtyId': subSpecialtyId,
        'isPrimary': isPrimary,
      };
}

class DoctorLanguageModel {
  final String id;
  final String doctorId;
  final String languageId;
  final LanguageProficiency proficiency;

  DoctorLanguageModel({
    required this.id,
    required this.doctorId,
    required this.languageId,
    required this.proficiency,
  });

  factory DoctorLanguageModel.fromJson(Map<String, dynamic> json) {
    return DoctorLanguageModel(
      id: json['id']?.toString() ?? '',
      doctorId: json['doctorId']?.toString() ?? '',
      languageId: json['languageId']?.toString() ?? '',
      proficiency: LanguageProficiency.fromString(json['proficiency'] ?? 'FLUENT'),
    );
  }

  Map<String, dynamic> toJson() => {
        'doctorId': doctorId,
        'languageId': languageId,
        'proficiency': proficiency.value,
      };
}

class DoctorQualificationModel {
  final String qualId;
  final String doctorId;
  final String degree;
  final String institution;
  final String country;
  final int yearObtained;
  final int sortOrder;

  DoctorQualificationModel({
    required this.qualId,
    required this.doctorId,
    required this.degree,
    required this.institution,
    required this.country,
    required this.yearObtained,
    required this.sortOrder,
  });

  factory DoctorQualificationModel.fromJson(Map<String, dynamic> json) {
    return DoctorQualificationModel(
      qualId: json['qualId']?.toString() ?? '',
      doctorId: json['doctorId']?.toString() ?? '',
      degree: json['degree'] ?? '',
      institution: json['institution'] ?? '',
      country: json['country'] ?? '',
      yearObtained: json['yearObtained'] ?? 2020,
      sortOrder: json['sortOrder'] ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'doctorId': doctorId,
        'degree': degree,
        'institution': institution,
        'country': country,
        'yearObtained': yearObtained,
        'sortOrder': sortOrder,
      };
}

class DoctorDetailResponse extends DoctorModel {
  final List<DoctorClinicModel> clinics;
  final List<DoctorSpecialtyModel> specialties;
  final List<DoctorLanguageModel> languages;
  final List<DoctorQualificationModel> qualifications;

  DoctorDetailResponse({
    required super.doctorId,
    required super.userId,
    required super.fullName,
    required super.mohRegistrationNumber,
    required super.mohVerified,
    required super.title,
    super.bioEn,
    super.bioAr,
    required super.experienceYears,
    required super.overallRating,
    required super.reviewCount,
    required super.consultationFeeSar,
    required super.isActive,
    super.createdAt,
    super.updatedAt,
    required this.clinics,
    required this.specialties,
    required this.languages,
    required this.qualifications,
  });

  factory DoctorDetailResponse.fromJson(Map<String, dynamic> json) {
    final docJson = json['doctor'] ?? json;
    final base = DoctorModel.fromJson(docJson);

    return DoctorDetailResponse(
      doctorId: base.doctorId,
      userId: base.userId,
      fullName: base.fullName,
      mohRegistrationNumber: base.mohRegistrationNumber,
      mohVerified: base.mohVerified,
      title: base.title,
      bioEn: base.bioEn,
      bioAr: base.bioAr,
      experienceYears: base.experienceYears,
      overallRating: base.overallRating,
      reviewCount: base.reviewCount,
      consultationFeeSar: base.consultationFeeSar,
      isActive: base.isActive,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
      clinics: (json['clinics'] as List? ?? []).map((e) => DoctorClinicModel.fromJson(e)).toList(),
      specialties: (json['specialties'] as List? ?? []).map((e) => DoctorSpecialtyModel.fromJson(e)).toList(),
      languages: (json['languages'] as List? ?? []).map((e) => DoctorLanguageModel.fromJson(e)).toList(),
      qualifications: (json['qualifications'] as List? ?? []).map((e) => DoctorQualificationModel.fromJson(e)).toList(),
    );
  }
}
