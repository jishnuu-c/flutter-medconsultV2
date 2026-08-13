import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

/// Mirrors file.service.ts's FileMetadataResponseDto.
class ChatFileMetadata {
  final String fileId;
  final String? uploadedById;
  final String? uploadedByName;
  final String? originalFilename;
  final String? mimeType;
  final int? sizeBytes;
  final String? category;
  final String? createdAt;

  ChatFileMetadata({
    required this.fileId,
    this.uploadedById,
    this.uploadedByName,
    this.originalFilename,
    this.mimeType,
    this.sizeBytes,
    this.category,
    this.createdAt,
  });

  factory ChatFileMetadata.fromJson(Map<String, dynamic> json) {
    return ChatFileMetadata(
      fileId: json['fileId']?.toString() ?? '',
      uploadedById: json['uploadedById']?.toString(),
      uploadedByName: json['uploadedByName']?.toString(),
      originalFilename: json['originalFilename']?.toString(),
      mimeType: json['mimeType']?.toString(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      category: json['category']?.toString(),
      createdAt: json['createdAt']?.toString(),
    );
  }
}

/// Mirrors file.service.ts (FileService): uploadChatFile / getFileMetadata /
/// downloadFile, same endpoints under /api/medconsult/files/.
class ChatFileService {
  final Dio dio;
  ChatFileService({required this.dio});

  Future<ChatFileMetadata> uploadChatFile(
    List<int> bytes,
    String filename, {
    String? mimeType,
    String? patientId,
  }) async {
    final form = FormData.fromMap({
      'category': 'CHAT_ATTACHMENT',
      if (patientId != null) 'patientId': patientId,
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: mimeType != null ? MediaType.parse(mimeType) : null,
      ),
    });
    final res = await dio.post('/api/medconsult/files/', data: form);
    return ChatFileMetadata.fromJson(Map<String, dynamic>.from(res.data));
  }

  Future<ChatFileMetadata> getFileMetadata(String fileId) async {
    final res = await dio.get('/api/medconsult/files/$fileId/metadata');
    return ChatFileMetadata.fromJson(Map<String, dynamic>.from(res.data));
  }

  Future<List<int>> downloadFile(String fileId) async {
    final res = await dio.get<List<int>>(
      '/api/medconsult/files/$fileId/download',
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data ?? [];
  }
}

final chatFileServiceProvider = Provider<ChatFileService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return ChatFileService(dio: dio);
});
