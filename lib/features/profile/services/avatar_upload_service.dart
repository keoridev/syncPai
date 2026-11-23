import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Сервис сжатия и загрузки пользовательских аватаров в Supabase Storage (`avatars`).
/// Обеспечивает единый HTTPS URL для мгновенной синхронизации между Android и Windows.
class AvatarUploadService {
  AvatarUploadService._();

  static const String storageBucket = 'avatars';
  static const int defaultMaxDimension = 512;
  static const int defaultJpegQuality = 85;

  /// Определяет, является ли строка локальным путём устройства (не пригодным для других устройств).
  static bool isLocalFilePath(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return false;
    }
    return trimmed.startsWith('/') ||
        trimmed.contains(':\\') ||
        trimmed.contains(':/') ||
        lower.startsWith('file://') ||
        lower.contains('custom_avatar');
  }

  /// Пропорционально сжимает изображение до [maxDimension]px и кодирует в JPEG с качеством [quality].
  static Uint8List compressAvatarToJpeg(
    Uint8List rawBytes, {
    int maxDimension = defaultMaxDimension,
    int quality = defaultJpegQuality,
  }) {
    if (rawBytes.isEmpty) return rawBytes;
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return rawBytes;

      img.Image processed = decoded;
      if (decoded.width > maxDimension || decoded.height > maxDimension) {
        final scale = maxDimension / math.max(decoded.width, decoded.height);
        final targetW = math.max(1, (decoded.width * scale).round());
        final targetH = math.max(1, (decoded.height * scale).round());
        processed = img.copyResize(
          decoded,
          width: targetW,
          height: targetH,
          interpolation: img.Interpolation.average,
        );
      }

      return Uint8List.fromList(img.encodeJpg(processed, quality: quality));
    } catch (e) {
      debugPrint('[AvatarUpload] Image compression fallback to raw bytes: $e');
      return rawBytes;
    }
  }

  /// Сжимает и загружает байты аватара в Supabase Storage `avatars/<user_id>/avatar_<timestamp>.jpg`
  /// и возвращает публичный HTTPS URL.
  static Future<String?> uploadAvatarBytes({
    required Uint8List bytes,
    SupabaseClient? clientOverride,
    String? userIdOverride,
    int? timestampMs,
  }) async {
    if (bytes.isEmpty) return null;

    SupabaseClient? client = clientOverride;
    if (client == null) {
      try {
        client = Supabase.instance.client;
      } catch (_) {
        return null;
      }
    }

    final userId = userIdOverride ??
        client.auth.currentSession?.user.id ??
        client.auth.currentUser?.id;
    if (userId == null || userId.trim().isEmpty) {
      return null;
    }

    try {
      final compressed = compressAvatarToJpeg(bytes);
      final ts = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
      final objectPath = '$userId/avatar_$ts.jpg';

      await client.storage.from(storageBucket).uploadBinary(
            objectPath,
            compressed,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              cacheControl: '3600',
              upsert: true,
            ),
          );

      final publicUrl = client.storage.from(storageBucket).getPublicUrl(objectPath);
      return publicUrl;
    } catch (e) {
      debugPrint('[AvatarUpload] Upload to Supabase Storage failed: $e');
      return null;
    }
  }

  /// Читает локальный файл с диска, сжимает и загружает в Supabase Storage.
  static Future<String?> uploadLocalAvatarFile(
    String filePath, {
    SupabaseClient? clientOverride,
    String? userIdOverride,
  }) async {
    try {
      final cleanPath = filePath.startsWith('file://')
          ? Uri.parse(filePath).toFilePath()
          : filePath;
      final file = File(cleanPath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return uploadAvatarBytes(
        bytes: bytes,
        clientOverride: clientOverride,
        userIdOverride: userIdOverride,
      );
    } catch (e) {
      debugPrint('[AvatarUpload] Failed reading local file for upload: $e');
      return null;
    }
  }
}
