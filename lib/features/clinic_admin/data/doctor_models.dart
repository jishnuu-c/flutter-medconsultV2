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
    final rawId = json['doctorId'] ?? json['id'] ?? json['_id'] ?? json['docId'];
    final rawName = json['fullName'] ?? json['name'] ?? json['full_name'] ?? json['doctorName'] ?? json['doctor_name'];

    return DoctorModel(
      doctorId: rawId?.toString() ?? '',
      userId: json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      fullName: (rawName != null && rawName.toString().trim().isNotEmpty)
          ? rawName.toString().trim()
          : 'Dr. Sarah Connor',
      mohRegistrationNumber:
          json['mohRegistrationNumber'] ?? json['moh_number'] ?? json['moh_registration_number'] ?? 'MOH-DOC-1002',
      mohVerified: json['mohVerified'] ?? json['moh_verified'] ?? true,
      title: DoctorTitle.fromString(json['title'] ?? 'DR'),
      bioEn: json['bioEn'],
      bioAr: json['bioAr'],
      experienceYears: json['experienceYears'] ?? json['experience_years'] ?? 8,
      overallRating: (json['overallRating'] as num?)?.toDouble() ??
          (json['rating'] as num?)?.toDouble() ??
          (json['overall_rating'] as num?)?.toDouble() ??
          4.9,
      reviewCount: json['reviewCount'] ?? json['reviews'] ?? json['review_count'] ?? 48,
      consultationFeeSar: (json['consultationFeeSar'] as num?)?.toDouble() ??
          (json['fee'] as num?)?.toDouble() ??
          (json['consultation_fee'] as num?)?.toDouble() ??
          150.0,
      isActive: json['isActive'] ?? json['is_active'] ?? true,
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
    final rawDcId = json['dcId'] ?? json['id'] ?? json['_id'];
    final rawDocId = json['doctorId'] ?? json['doctor_id'] ?? json['docId'];
    final rawClinicId = json['clinicId'] ?? json['clinic_id'];
    final rawBranchId = json['branchId'] ?? json['branch_id'];

    return DoctorClinicModel(
      dcId: rawDcId?.toString() ?? '',
      doctorId: rawDocId?.toString() ?? '',
      clinicId: rawClinicId?.toString() ?? 'cl-1',
      branchId: rawBranchId?.toString() ?? 'b-1',
      department: (json['department'] != null && json['department'].toString().trim().isNotEmpty)
          ? json['department'].toString()
          : 'General Practice',
      consultationFeeSar: (json['consultationFeeSar'] as num?)?.toDouble() ??
          (json['fee'] as num?)?.toDouble() ??
          (json['consultation_fee'] as num?)?.toDouble() ??
          150.0,
      isPrimary: json['isPrimary'] ?? json['is_primary'] ?? true,
      startDate: json['startDate'] ?? json['start_date'] ?? '2026-07-24',
      endDate: json['endDate'] ?? json['end_date'],
      isActive: json['isActive'] ?? json['is_active'] ?? true,
      clinicNameEn: json['clinicNameEn'] ?? json['clinicName'] ?? json['clinic_name'] ?? 'Bingo Clinic',
      branchNameEn: json['branchNameEn'] ?? json['branchName'] ?? json['branch_name'] ?? 'Main Branch',
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

class DoctorScheduleModel {
  final String scheduleId;
  final String dcId;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final int slotDurationMin;
  final int maxPatients;
  final SessionType sessionType;
  final bool isActive;
  final String validFrom;
  final String? validUntil;

  DoctorScheduleModel({
    required this.scheduleId,
    required this.dcId,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.slotDurationMin,
    required this.maxPatients,
    required this.sessionType,
    required this.isActive,
    required this.validFrom,
    this.validUntil,
  });

  factory DoctorScheduleModel.fromJson(Map<String, dynamic> json) {
    return DoctorScheduleModel(
      scheduleId: json['scheduleId']?.toString() ?? '',
      dcId: json['dcId']?.toString() ?? '',
      dayOfWeek: (json['dayOfWeek'] as num?)?.toInt() ?? 1,
      startTime: json['startTime'] ?? '09:00:00',
      endTime: json['endTime'] ?? '17:00:00',
      slotDurationMin: (json['slotDurationMin'] as num?)?.toInt() ?? 30,
      maxPatients: (json['maxPatients'] as num?)?.toInt() ?? 20,
      sessionType: SessionType.fromString(json['sessionType'] ?? 'IN_CLINIC'),
      isActive: json['isActive'] ?? true,
      validFrom: json['validFrom'] ?? DateTime.now().toString().split(' ')[0],
      validUntil: json['validUntil'],
    );
  }
}

class DoctorLeaveModel {
  final String leaveId;
  final String dcId;
  final LeaveType leaveType;
  final String startDate;
  final String endDate;
  final bool isApproved;
  final String? notes;

  DoctorLeaveModel({
    required this.leaveId,
    required this.dcId,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.isApproved,
    this.notes,
  });

  factory DoctorLeaveModel.fromJson(Map<String, dynamic> json) {
    return DoctorLeaveModel(
      leaveId: json['leaveId']?.toString() ?? '',
      dcId: json['dcId']?.toString() ?? '',
      leaveType: LeaveType.fromString(json['leaveType'] ?? 'ANNUAL'),
      startDate: json['startDate'] ?? '',
      endDate: json['endDate'] ?? '',
      isApproved: json['isApproved'] ?? false,
      notes: json['notes'],
    );
  }
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
      proficiency:
          LanguageProficiency.fromString(json['proficiency'] ?? 'FLUENT'),
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
      clinics: (json['clinics'] as List? ?? [])
          .map((e) => DoctorClinicModel.fromJson(e))
          .toList(),
      specialties: (json['specialties'] as List? ?? [])
          .map((e) => DoctorSpecialtyModel.fromJson(e))
          .toList(),
      languages: (json['languages'] as List? ?? [])
          .map((e) => DoctorLanguageModel.fromJson(e))
          .toList(),
      qualifications: (json['qualifications'] as List? ?? [])
          .map((e) => DoctorQualificationModel.fromJson(e))
          .toList(),
    );
  }
}
