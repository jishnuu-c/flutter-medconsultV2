import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

/// Mirrors review.service.ts's ClinicReviewResponse — public-facing review
/// left by a patient after a completed visit.
class ClinicReviewModel {
  final String reviewId;
  final String clinicId;
  final String patientId;
  final String patientName;
  final String appointmentId;
  final int rating;
  final int? ratingCleanliness;
  final int? ratingStaff;
  final int? ratingWait;
  final String? reviewText;
  final bool isPublished;
  final bool isAnonymous;
  final String? createdAt;
  final String? patientAvatarUrl;

  ClinicReviewModel({
    required this.reviewId,
    required this.clinicId,
    required this.patientId,
    required this.patientName,
    required this.appointmentId,
    required this.rating,
    this.ratingCleanliness,
    this.ratingStaff,
    this.ratingWait,
    this.reviewText,
    required this.isPublished,
    required this.isAnonymous,
    this.createdAt,
    this.patientAvatarUrl,
  });

  factory ClinicReviewModel.fromJson(Map<String, dynamic> json) {
    return ClinicReviewModel(
      reviewId: json['reviewId']?.toString() ?? '',
      clinicId: json['clinicId']?.toString() ?? '',
      patientId: json['patientId']?.toString() ?? '',
      patientName: json['patientName']?.toString() ?? '',
      appointmentId: json['appointmentId']?.toString() ?? '',
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      ratingCleanliness: (json['ratingCleanliness'] as num?)?.toInt(),
      ratingStaff: (json['ratingStaff'] as num?)?.toInt(),
      ratingWait: (json['ratingWait'] as num?)?.toInt(),
      reviewText: json['reviewText']?.toString(),
      isPublished: json['isPublished'] ?? true,
      isAnonymous: json['isAnonymous'] ?? false,
      createdAt: json['createdAt']?.toString(),
      patientAvatarUrl: json['patientAvatarUrl']?.toString(),
    );
  }
}

class ReviewService {
  final Dio dio;
  ReviewService({required this.dio});

  /// Mirrors review.service.ts's getClinicReviews — public paged review
  /// listing for a clinic. Accepts either a bare list or a Spring Page
  /// envelope ({content: [...]}) from the backend, same defensive handling
  /// Angular's loadClinicData() does.
  Future<List<ClinicReviewModel>> getClinicReviews(String clinicId,
      {int page = 0, int size = 20}) async {
    final res = await dio.get(
      '/api/medconsult/reviews/clinics/$clinicId',
      queryParameters: {'page': page, 'size': size},
    );
    final data = res.data;
    List list;
    if (data is List) {
      list = data;
    } else if (data is Map && data['content'] is List) {
      list = data['content'] as List;
    } else if (data is Map && data['data'] is List) {
      list = data['data'] as List;
    } else {
      list = const [];
    }
    return list
        .whereType<Map>()
        .map((e) => ClinicReviewModel.fromJson(e.cast<String, dynamic>()))
        .toList();
  }
}

final reviewServiceProvider = Provider<ReviewService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return ReviewService(dio: dio);
});
