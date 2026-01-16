import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class PhotoService {
  final SupabaseClient _client = Supabase.instance.client;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Uuid _uuid = const Uuid();

  /// Uploads a photo to Firebase Storage and saves metadata to Supabase
  /// 
  /// [jobId] - The ID of the job
  /// [categoryId] - The ID of the photo category
  /// [photoFile] - The photo file to upload (for non-web platforms)
  /// [photoBytes] - The photo bytes to upload (for web platform)
  /// [fileExtension] - File extension (required when using photoBytes, e.g., 'jpg', 'png')
  Future<void> uploadPhoto(
    String jobId,
    String categoryId, {
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
      final firebasePath = 'jobs/$jobId/$categoryId/$filename';

      print('[PhotoService] uploadPhoto() - Generated filename: $filename');
      print('[PhotoService] uploadPhoto() - Firebase path: $firebasePath');
      print('[PhotoService] uploadPhoto() - Platform: ${kIsWeb ? "Web" : "Non-web"}');

      // Upload to Firebase Storage
      final storageRef = _storage.ref().child(firebasePath);
      
      if (kIsWeb) {
        // For web, use putData with bytes
        if (photoBytes == null) {
          throw ArgumentError('photoBytes is required when running on web');
        }
        await storageRef.putData(
          photoBytes,
          SettableMetadata(contentType: 'image/$extension'),
        );
      } else {
        // For non-web platforms, use putFile
        if (photoFile == null) {
          throw ArgumentError('photoFile is required when not running on web');
        }
        await storageRef.putFile(photoFile);
      }

      print('[PhotoService] uploadPhoto() - File uploaded to Firebase Storage');

      // Get download URL
      final downloadUrl = await storageRef.getDownloadURL();
      print('[PhotoService] uploadPhoto() - Download URL: $downloadUrl');

      // Save metadata to Supabase
      await _client.from('photos').insert({
        'job_id': jobId,
        'category_id': categoryId,
        'firebase_path': downloadUrl, // Store full Firebase download URL
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
  /// Returns a list of Firebase download URLs
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

  /// Deletes a photo by its Firebase path URL
  /// 
  /// [photoUrl] - The Firebase download URL of the photo to delete
  /// [jobId] - The ID of the job (for metadata deletion)
  Future<void> deletePhoto(String photoUrl, String jobId) async {
    try {
      print('[PhotoService] deletePhoto() - Deleting photo: $photoUrl');

      // Delete from Firebase Storage
      try {
        final storageRef = _storage.refFromURL(photoUrl);
        await storageRef.delete();
        print('[PhotoService] deletePhoto() - Photo deleted from Firebase Storage');
      } catch (e) {
        print('[PhotoService] deletePhoto() - Error deleting from Firebase: $e');
        // Continue to delete metadata even if Firebase deletion fails
      }

      // Delete metadata from Supabase
      await _client
          .from('photos')
          .delete()
          .eq('firebase_path', photoUrl)
          .eq('job_id', jobId);

      print('[PhotoService] deletePhoto() - Photo metadata deleted from Supabase');
    } catch (e) {
      print('[PhotoService] deletePhoto() - Error: $e');
      rethrow;
    }
  }
}
