import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../services/supabase_service.dart';

class PhotoService {
  static final _storage = SupabaseService().client.storage;

  /// Uploads a photo to Supabase Storage and returns the download URL.
  /// Supports both mobile (file path) and web (XFile or bytes)
  static Future<String?> uploadPhoto(
    dynamic imageSource,
    String folder, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      Uint8List? bytes;

      if (imageSource is String) {
        // Mobile: file path
        final file = File(imageSource);
        if (!await file.exists()) {
          debugPrint('[PhotoService] File does not exist at path: $imageSource');
          return null;
        }
        bytes = await file.readAsBytes();
      } else if (imageSource is XFile) {
        // Web/mobile: XFile
        bytes = await imageSource.readAsBytes();
      } else {
        debugPrint('[PhotoService] Unsupported image source type');
        return null;
      }

      // 2. Upload to Supabase Storage (using 'photos' bucket)
      final fileName = '${const Uuid().v4()}.jpg';
      final pathInBucket = '$folder/$fileName';
      
      // Upload bytes
      await _storage
          .from('photos')
          .uploadBinary(pathInBucket, bytes);
      
      onProgress?.call(1.0);

      // Get public URL
      final url = _storage
          .from('photos')
          .getPublicUrl(pathInBucket);
      
      debugPrint('[PhotoService] Upload successful: $url');
      return url;
    } catch (e) {
      debugPrint('[PhotoService] Error uploading photo: $e');
      return null;
    }
  }

  /// Batch upload — already-https paths pass through unchanged.
  static Future<List<String>> uploadPhotos(List<String> paths, String folder) async {
    final urls = <String>[];
    for (final path in paths) {
      if (path.startsWith('http')) {
        urls.add(path);
        continue;
      }
      final url = await uploadPhoto(path, folder);
      if (url != null) urls.add(url);
    }
    return urls;
  }

  /// Deletes a photo from Supabase Storage by its download URL.
  /// Silent no-op for non-Storage URLs or network failures.
  static Future<void> deleteByUrl(String url) async {
    try {
      // Parse the bucket path from the URL (assuming it's a Supabase Storage URL)
      // Typical URL format: https://<project>.supabase.co/storage/v1/object/public/photos/...
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      if (pathSegments.length < 5) return;

      // Extract the path after 'public'
      final bucketName = pathSegments[4];
      final filePath = pathSegments.sublist(5).join('/');

      await _storage.from(bucketName).remove([filePath]);
      debugPrint('[PhotoService] Deleted: $url');
    } catch (e) {
      debugPrint('[PhotoService] deleteByUrl ignored: $e');
    }
  }
}
