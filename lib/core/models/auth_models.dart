enum UserRole {
  PATIENT('PATIENT'),
  DOCTOR('DOCTOR'),
  CLINIC_ADMIN('CLINIC_ADMIN'),
  SYSTEM_ADMIN('SYSTEM_ADMIN');

  final String value;
  const UserRole(this.value);

  static UserRole fromString(String? role) {
    if (role == null || role.isEmpty) return UserRole.PATIENT;
    final clean = role.toUpperCase().trim();
    return UserRole.values.firstWhere(
      (e) => e.value == clean || e.name == clean,
      orElse: () => UserRole.PATIENT,
    );
  }
}

enum Gender {
  MALE('MALE'),
  FEMALE('FEMALE'),
  PREFER_NOT_TO_SAY('PREFER_NOT_TO_SAY');

  final String value;
  const Gender(this.value);

  static Gender fromString(String? val) {
    if (val == null || val.isEmpty) return Gender.PREFER_NOT_TO_SAY;
    final clean = val.toUpperCase().trim();
    return Gender.values.firstWhere(
      (e) => e.value == clean || e.name == clean,
      orElse: () => Gender.PREFER_NOT_TO_SAY,
    );
  }
}

class UserModel {
  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final String? avatarUrl;
  final Gender? gender;
  final String? phone;

  UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.avatarUrl,
    this.gender,
    this.phone,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? json['userId']?.toString() ?? '',
      email: json['email'] ?? '',
      fullName: json['fullName'] ?? json['name'] ?? json['username'] ?? '',
      role: UserRole.fromString(json['role'] ?? json['userRole']),
      avatarUrl: json['avatarUrl'] ?? json['avatar'],
      gender: json['gender'] != null ? Gender.fromString(json['gender']) : null,
      phone: json['phone'] ?? json['phoneNumber'] ?? json['mobile'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'fullName': fullName,
      'role': role.value,
      'avatarUrl': avatarUrl,
      'gender': gender?.value,
      'phone': phone,
    };
  }

  String get initials {
    if (fullName.isEmpty) return 'U';
    final names = fullName.trim().split(' ');
    if (names.length >= 2) {
      return (names[0][0] + names[1][0]).toUpperCase();
    }
    return fullName.substring(0, fullName.length >= 2 ? 2 : 1).toUpperCase();
  }
}

class LoginRequestDto {
  final String email;
  final String password;

  LoginRequestDto({required this.email, required this.password});

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
      };
}

class RegisterRequestDto {
  final String email;
  final String password;
  final String fullName;
  final UserRole role;
  final Gender? gender;
  final String? phone;

  RegisterRequestDto({
    required this.email,
    required this.password,
    required this.fullName,
    required this.role,
    this.gender,
    this.phone,
  });

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
        'fullName': fullName,
        'role': role.value,
        if (gender != null) 'gender': gender!.value,
        if (phone != null) 'phone': phone,
      };
}

class AuthResponseDto {
  final String token;
  final UserModel? user;

  AuthResponseDto({required this.token, this.user});

  factory AuthResponseDto.fromJson(dynamic json) {
    if (json is String) {
      return AuthResponseDto(token: json);
    }
    if (json is Map<String, dynamic>) {
      final token = json['token'] ??
          json['accessToken'] ??
          json['jwt'] ??
          json['jwtToken'] ??
          json['data']?['token'] ??
          json['data']?['accessToken'] ??
          '';
      final userData = json['user'] ?? json['data']?['user'] ?? json['userDto'];
      return AuthResponseDto(
        token: token.toString(),
        user: userData is Map<String, dynamic> ? UserModel.fromJson(userData) : null,
      );
    }
    return AuthResponseDto(token: '');
  }
}
