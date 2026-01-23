import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../services/job_service.dart';
import '../services/photo_service.dart';

class PhotoUploadScreen extends StatefulWidget {
  final String jobId;
  final bool readOnly;

  const PhotoUploadScreen({
    super.key,
    required this.jobId,
    this.readOnly = false,
  });

  @override
  State<PhotoUploadScreen> createState() => _PhotoUploadScreenState();
}

class _PhotoUploadScreenState extends State<PhotoUploadScreen> {
  final JobService _jobService = JobService();
  final PhotoService _photoService = PhotoService();
  SupabaseClient get _client => Supabase.instance.client;
  final ImagePicker _imagePicker = ImagePicker();

  String? _jobAddress;
  List<Map<String, dynamic>> _categories = [];
  Map<String, List<String>> _photosByCategory = {}; // Store download URLs
  Map<String, bool> _uploadingByCategory = {}; // Track upload state per category
  bool _isLoadingCategories = true;
  bool _isLoadingAddress = true;
  bool _photosLoaded = false; // Flag to prevent reloading photos on rebuilds
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // Reset photos loaded flag when explicitly reloading data (e.g., retry)
    _photosLoaded = false;
    await Future.wait([
      _loadJobAddress(),
      _loadCategories(),
    ]);
  }

  Future<void> _loadJobAddress() async {
    try {
      final job = await _client
          .from('jobs')
          .select('address')
          .eq('id', widget.jobId)
          .maybeSingle();

      setState(() {
        _jobAddress = job?['address'] as String?;
        _isLoadingAddress = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load job address: ${e.toString()}';
        _isLoadingAddress = false;
      });
    }
  }

  Future<void> _loadCategories() async {
    try {
      print('Loading categories...');
      
      final response = await _client
          .from('photo_categories')
          .select()
          .order('sort_order', ascending: true);

      print('Categories response: $response');
      final newCategories = List<Map<String, dynamic>>.from(response);
      
      setState(() {
        _categories = newCategories;
        _isLoadingCategories = false;
        // Initialize photo lists for each category
        for (var category in _categories) {
          final categoryId = category['id'].toString();
          _photosByCategory[categoryId] ??= [];
        }
      });

      // Load existing photos for each category only once
      if (!_photosLoaded) {
        await _loadExistingPhotos();
      }
    } catch (e) {
      print('Error loading categories: $e');
      setState(() {
        _errorMessage = 'Failed to load categories: ${e.toString()}';
        _isLoadingCategories = false;
      });
    }
  }

  Future<void> _loadExistingPhotos() async {
    // Load all photos first, then update state once
    final Map<String, List<String>> loadedPhotos = {};
    
    for (var category in _categories) {
      final categoryId = category['id'].toString();
      try {
        final photoUrls = await _photoService.getPhotosForCategory(
          widget.jobId,
          categoryId,
        );
        loadedPhotos[categoryId] = photoUrls;
      } catch (e) {
        print('Error loading photos for category $categoryId: $e');
        // Continue loading other categories even if one fails
        loadedPhotos[categoryId] = [];
      }
    }
    
    // Update state once with all loaded photos
    setState(() {
      _photosByCategory = loadedPhotos;
      _photosLoaded = true;
    });
  }

  Future<void> _addPhoto(String categoryId) async {
    ImageSource? source;
    
    // On iOS, skip dialog and go directly to gallery - iOS will show its own native picker
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      source = ImageSource.gallery;
    } else {
      // On Android/other platforms, show dialog to choose source
      source = await showDialog<ImageSource>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Select Photo Source'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Take Photo'),
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Choose from Gallery'),
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
              ],
            ),
          );
        },
      );
    }

    if (source == null) return;

    try {
      // Use ImagePicker directly with the selected source
      // ImageSource.camera opens camera directly
      // ImageSource.gallery opens photo library directly (no intermediate picker)
      // On iOS, ImageSource.gallery will show iOS native picker with camera/gallery options
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (image != null) {
        // Set uploading state
        setState(() {
          _uploadingByCategory[categoryId] = true;
        });

        try {
          // Read photo as bytes
          final bytes = await image.readAsBytes();
          final extension = image.name.split('.').last;
          
          // Find category name
          final category = _categories.firstWhere(
            (cat) => cat['id'].toString() == categoryId,
            orElse: () => {'name': 'Unknown'},
          );
          final categoryName = category['name'] as String? ?? 'Unknown';
          final address = _jobAddress ?? 'Unknown Address';
          
          // Upload photo
          await _photoService.uploadPhoto(
            widget.jobId,
            categoryId,
            address,
            categoryName,
            photoBytes: bytes,
            fileExtension: extension,
          );

          // Reload photos for this category
          final photoUrls = await _photoService.getPhotosForCategory(
            widget.jobId,
            categoryId,
          );

          setState(() {
            _photosByCategory[categoryId] = photoUrls;
            _uploadingByCategory[categoryId] = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Photo uploaded successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          setState(() {
            _uploadingByCategory[categoryId] = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to upload photo: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removePhoto(String categoryId, String photoUrl, int index) async {
    // Confirm deletion
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Photo'),
          content: const Text('Are you sure you want to delete this photo?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      // Delete from MinIO and Supabase
      await _photoService.deletePhoto(photoUrl, widget.jobId);

      // Remove from local state
      setState(() {
        _photosByCategory[categoryId]?.removeAt(index);
        // Button state will automatically re-check on rebuild
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete photo: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  bool _canSubmitForReview() {
    for (var category in _categories) {
      final isRequired = category['required'] == true;
      final categoryId = category['id'].toString();
      final photoCount = _photosByCategory[categoryId]?.length ?? 0;

      if (isRequired && photoCount < 1) {
        return false;
      }
    }
    return true;
  }

  Future<void> _submitForReview() async {
    if (!_canSubmitForReview()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one photo to all required categories'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // Update job status to 'pending_review' in Supabase
      await _jobService.completeJob(widget.jobId);

      if (mounted) {
        // Show success SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job submitted for review successfully'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate back to job screen
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit job: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.readOnly ? 'View Photos' : 'Upload Photos'),
        elevation: 2,
      ),
      body: _isLoadingCategories || _isLoadingAddress
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32.0),
                        child: Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red[700]),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Job Address Section
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16.0),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Job Address',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _jobAddress ?? 'N/A',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                    ),

                    // Categories List
                    Expanded(
                      child: _categories.isEmpty
                          ? const Center(
                              child: Text('No photo categories found'),
                            )
                          : ListView.builder(
                              primary: true,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(16.0),
                              itemCount: _categories.length,
                              itemBuilder: (context, index) {
                                final category = _categories[index];
                              final categoryId = category['id'].toString();
                              final categoryName = category['name'] as String? ?? 'Unnamed Category';
                              final isRequired = category['required'] == true;
                              final photoCount = _photosByCategory[categoryId]?.length ?? 0;
                              final photos = _photosByCategory[categoryId] ?? [];

                              return Card(
                                margin: const EdgeInsets.only(bottom: 16.0),
                                elevation: 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Category Header
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Text(
                                                  categoryName,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                ),
                                                if (isRequired) ...[
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '*',
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          // Photo Count Badge
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: photoCount > 0
                                                  ? Theme.of(context).colorScheme.primaryContainer
                                                  : Theme.of(context).colorScheme.surfaceContainerHighest,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              '$photoCount',
                                              style: TextStyle(
                                                color: photoCount > 0
                                                    ? Theme.of(context).colorScheme.onPrimaryContainer
                                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),

                                      // Add Photo Button (only show if not read-only)
                                      if (!widget.readOnly)
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            onPressed: _uploadingByCategory[categoryId] == true
                                                ? null
                                                : () => _addPhoto(categoryId),
                                            icon: _uploadingByCategory[categoryId] == true
                                                ? const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child: CircularProgressIndicator(strokeWidth: 2),
                                                  )
                                                : const Icon(Icons.camera_alt),
                                            label: Text(
                                              _uploadingByCategory[categoryId] == true
                                                  ? 'Uploading...'
                                                  : 'Add Photo',
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(vertical: 12),
                                            ),
                                          ),
                                        ),
                                      if (!widget.readOnly) const SizedBox(height: 16),
                                      const SizedBox(height: 16),

                                      // Photo Thumbnails
                                      if (photos.isNotEmpty)
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: List.generate(
                                            photos.length,
                                            (photoIndex) {
                                              return Stack(
                                                children: [
                                                  Container(
                                                    width: 80,
                                                    height: 80,
                                                    decoration: BoxDecoration(
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(
                                                        color: Colors.grey[300]!,
                                                      ),
                                                    ),
                                                    child: ClipRRect(
                                                      borderRadius: BorderRadius.circular(8),
                                                      child: Image.network(
                                                        photos[photoIndex],
                                                        fit: BoxFit.cover,
                                                        loadingBuilder: (context, child, loadingProgress) {
                                                          if (loadingProgress == null) return child;
                                                          return Center(
                                                            child: CircularProgressIndicator(
                                                              value: loadingProgress.expectedTotalBytes != null
                                                                  ? loadingProgress.cumulativeBytesLoaded /
                                                                      loadingProgress.expectedTotalBytes!
                                                                  : null,
                                                            ),
                                                          );
                                                        },
                                                        errorBuilder: (context, error, stackTrace) {
                                                          print('Image load error: $error');
                                                          return Tooltip(
                                                            message: error.toString(),
                                                            child: Icon(
                                                              Icons.error,
                                                              color: Colors.red,
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                  ),
                                                  if (!widget.readOnly)
                                                    Positioned(
                                                      top: -4,
                                                      right: -4,
                                                      child: IconButton(
                                                        icon: Container(
                                                          padding: const EdgeInsets.all(4),
                                                          decoration: BoxDecoration(
                                                            color: Colors.red,
                                                            shape: BoxShape.circle,
                                                          ),
                                                          child: const Icon(
                                                            Icons.close,
                                                            size: 16,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                        onPressed: () =>
                                                            _removePhoto(categoryId, photos[photoIndex], photoIndex),
                                                        padding: EdgeInsets.zero,
                                                        constraints: const BoxConstraints(),
                                                      ),
                                                    ),
                                                ],
                                              );
                                            },
                                          ),
                                        )
                                      else
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(vertical: 24),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[50],
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: Colors.grey[200]!,
                                              style: BorderStyle.solid,
                                            ),
                                          ),
                                          child: Text(
                                            'No photos added yet',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                    ),

                    // Submit Button (only show if not read-only)
                    if (!widget.readOnly)
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: SafeArea(
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _canSubmitForReview() ? _submitForReview : null,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                disabledBackgroundColor: Colors.grey[300],
                                disabledForegroundColor: Colors.grey[600],
                              ),
                              child: const Text(
                                'Submit for Review',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
