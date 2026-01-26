import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:minio/minio.dart';
import 'package:minio/io.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class PhotoService {
  final SupabaseClient _client = Supabase.instance.client;
  final Uuid _uuid = const Uuid();
  
  // MinIO configuration
  static const String _minioEndpoint = 'minio-api.entify.ca';
  static const String _bucket = 'hudson-photos';
  static const bool _useSSL = true;
  static const String _baseUrl = 'https://minio-api.entify.ca/hudson-photos';
  
  // Lazy initialization of MinIO client
  Minio? _minioClient;
  
  Minio get _minio {
    if (_minioClient == null) {
      // Try to get from dotenv first (for local development)
      String accessKey = dotenv.env['MINIO_ACCESS_KEY'] ?? '';
      String secretKey = dotenv.env['MINIO_SECRET_KEY'] ?? '';
      
      // For web deployments, also check if they're set via environment variables
      // that might be injected at build time (e.g., via --dart-define)
      if (accessKey.isEmpty) {
        // Try reading from const String if defined at build time
        // This would be set via: flutter build web --dart-define=MINIO_ACCESS_KEY=...
        accessKey = const String.fromEnvironment('MINIO_ACCESS_KEY', defaultValue: '');
      }
      if (secretKey.isEmpty) {
        secretKey = const String.fromEnvironment('MINIO_SECRET_KEY', defaultValue: '');
      }
      
      if (accessKey.isEmpty || secretKey.isEmpty) {
        throw Exception(
          'MINIO_ACCESS_KEY and MINIO_SECRET_KEY must be set.\n'
          'For local development: Set them in .env.local\n'
          'For deployment: Set them as environment variables in your deployment platform '
          'or use --dart-define flags during build'
        );
      }
      
      _minioClient = Minio(
        endPoint: _minioEndpoint,
        accessKey: accessKey,
        secretKey: secretKey,
        useSSL: _useSSL,
      );
    }
    return _minioClient!;
  }

  /// Sanitizes a string for use in file paths
  /// Converts to lowercase, replaces spaces/underscores with hyphens,
  /// removes non-alphanumeric characters (except hyphens), and collapses multiple hyphens
  String _sanitizeForPath(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_]'), '-') // Replace spaces and underscores with hyphens
        .replaceAll(RegExp(r'[^a-z0-9\-]'), '') // Remove non-alphanumeric (except hyphens)
        .replaceAll(RegExp(r'-+'), '-') // Collapse multiple hyphens into one
        .replaceAll(RegExp(r'^-|-$'), ''); // Remove leading/trailing hyphens
  }

  /// Uploads a photo to MinIO Storage and saves metadata to Supabase
  /// 
  /// [jobId] - The ID of the job
  /// [categoryId] - The ID of the photo category
  /// [address] - The job address (for path structure)
  /// [categoryName] - The category name (for path structure)
  /// [photoFile] - The photo file to upload (for non-web platforms)
  /// [photoBytes] - The photo bytes to upload (for web platform)
  /// [fileExtension] - File extension (required when using photoBytes, e.g., 'jpg', 'png')
  Future<void> uploadPhoto(
    String jobId,
    String categoryId,
    String address,
    String categoryName, {
    File? photoFile,
    Uint8List? photoBytes,
    String? fileExtension,
  }) async {
    try {
      print('[PhotoService] uploadPhoto() - Starting upload for job: $jobId, category: $categoryId');

      // Determine file extension
      String extension;
      if (photoFile != null) {
        extension = photoFile.path.split('.').last;
      } else if (fileExtension != null) {
        extension = fileExtension;
      } else {
        throw ArgumentError('Either photoFile or photoBytes with fileExtension must be provided');
      }

      // Generate unique filename
      final filename = '${_uuid.v4()}.$extension';
      
      // Build path with sanitized address and category name
      final sanitizedAddress = _sanitizeForPath(address);
      final sanitizedCategoryName = _sanitizeForPath(categoryName);
      final shortJobId = jobId.length > 8 ? jobId.substring(0, 8) : jobId;
      final objectPath = 'jobs/${sanitizedAddress}_$shortJobId/$sanitizedCategoryName/$filename';

      print('[PhotoService] uploadPhoto() - Generated filename: $filename');
      print('[PhotoService] uploadPhoto() - MinIO object path: $objectPath');
      print('[PhotoService] uploadPhoto() - Platform: ${kIsWeb ? "Web" : "Non-web"}');

      // Upload to MinIO Storage
      if (kIsWeb) {
        // For web, use putObject with bytes stream
        if (photoBytes == null) {
          throw ArgumentError('photoBytes is required when running on web');
        }
        // Convert bytes to stream for S3-compatible API
        final stream = Stream<Uint8List>.value(photoBytes);
        await _minio.putObject(
          _bucket,
          objectPath,
          stream,
          size: photoBytes.length,
          metadata: {'Content-Type': 'image/$extension'},
        );
      } else {
        // For non-web platforms, use fPutObject with file
        if (photoFile == null) {
          throw ArgumentError('photoFile is required when not running on web');
        }
        await _minio.fPutObject(
          _bucket,
          objectPath,
          photoFile.path,
          metadata: {'Content-Type': 'image/$extension'},
        );
      }

      print('[PhotoService] uploadPhoto() - File uploaded to MinIO Storage');

      // Generate public URL
      final downloadUrl = '$_baseUrl/$objectPath';
      print('[PhotoService] uploadPhoto() - Download URL: $downloadUrl');

      // Save metadata to Supabase
      await _client.from('photos').insert({
        'job_id': jobId,
        'category_id': categoryId,
        'firebase_path': downloadUrl, // Store MinIO URL (keeping column name for now)
      });

      print('[PhotoService] uploadPhoto() - Metadata saved to Supabase');
    } catch (e) {
      print('[PhotoService] uploadPhoto() - Error: $e');
      rethrow;
    }
  }

  /// Gets all photos for a specific job and category
  /// 
  /// [jobId] - The ID of the job
  /// [categoryId] - The ID of the photo category
  /// Returns a list of MinIO download URLs
  Future<List<String>> getPhotosForCategory(
    String jobId,
    String categoryId,
  ) async {
    try {
      print('[PhotoService] getPhotosForCategory() - Fetching photos for job: $jobId, category: $categoryId');

      final response = await _client
          .from('photos')
          .select('firebase_path')
          .eq('job_id', jobId)
          .eq('category_id', categoryId);

      print('[PhotoService] getPhotosForCategory() - Query result: $response');

      final List<String> downloadUrls = [];
      if (response != null) {
        for (var photo in response) {
          final url = photo['firebase_path'] as String?;
          if (url != null) {
            downloadUrls.add(url);
          }
        }
      }

      print('[PhotoService] getPhotosForCategory() - Found ${downloadUrls.length} photos');
      return downloadUrls;
    } catch (e) {
      print('[PhotoService] getPhotosForCategory() - Error: $e');
      rethrow;
    }
  }

  /// Gets the total count of photos for a specific job
  /// 
  /// [jobId] - The ID of the job
  /// Returns the total number of photos for the job
  Future<int> getPhotoCountForJob(String jobId) async {
    try {
      print('[PhotoService] getPhotoCountForJob() - Counting photos for job: $jobId');

      final response = await _client
          .from('photos')
          .select('id')
          .eq('job_id', jobId);

      final count = response.length;
      print('[PhotoService] getPhotoCountForJob() - Found $count photos');
      return count;
    } catch (e) {
      print('[PhotoService] getPhotoCountForJob() - Error: $e');
      rethrow;
    }
  }

  /// Deletes a photo by its MinIO URL
  /// 
  /// [photoUrl] - The MinIO download URL of the photo to delete
  /// [jobId] - The ID of the job (for metadata deletion)
  Future<void> deletePhoto(String photoUrl, String jobId) async {
    try {
      print('[PhotoService] deletePhoto() - Deleting photo: $photoUrl');

      // Extract object path from URL
      // URL format: https://minio-api.entify.ca/hudson-photos/jobs/{sanitizedAddress}_{jobId}/{sanitizedCategoryName}/{filename}
      // Object path: jobs/{sanitizedAddress}_{jobId}/{sanitizedCategoryName}/{filename}
      String objectPath;
      if (photoUrl.startsWith(_baseUrl)) {
        objectPath = photoUrl.substring(_baseUrl.length + 1); // +1 to remove leading /
      } else {
        // Fallback: assume the URL contains the path after the bucket name
        final parts = photoUrl.split('/hudson-photos/');
        if (parts.length > 1) {
          objectPath = parts[1];
        } else {
          throw Exception('Invalid MinIO URL format: $photoUrl');
        }
      }

      print('[PhotoService] deletePhoto() - Extracted object path: $objectPath');

      // Delete from MinIO Storage
      Exception? minioError;
      try {
        await _minio.removeObject(_bucket, objectPath);
        print('[PhotoService] deletePhoto() - Photo deleted from MinIO Storage');
      } catch (e) {
        minioError = e is Exception ? e : Exception(e.toString());
        print('[PhotoService] deletePhoto() - Error deleting from MinIO: $minioError');
        // Continue to delete metadata even if MinIO deletion fails
      }

      // Delete metadata from Supabase
      try {
        final result = await _client
            .from('photos')
            .delete()
            .eq('firebase_path', photoUrl)
            .eq('job_id', jobId);
        print('[PhotoService] deletePhoto() - Photo metadata deleted from Supabase');
        
        // Check if any rows were actually deleted
        if (result.isEmpty) {
          print('[PhotoService] deletePhoto() - Warning: No photo record found in Supabase to delete');
        }
      } catch (e) {
        print('[PhotoService] deletePhoto() - Error deleting from Supabase: $e');
        // If Supabase deletion fails, rethrow the error
        rethrow;
      }

      // If MinIO deletion failed, throw an error to notify the user
      // (Supabase deletion already succeeded, so database is clean)
      if (minioError != null) {
        throw Exception('Photo deleted from database but failed to delete from storage: $minioError');
      }
    } catch (e) {
      print('[PhotoService] deletePhoto() - Error: $e');
      rethrow;
    }
  }
}
