import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../services/job_service.dart';
import '../services/photo_service.dart';
import '../services/pdf_service.dart';

class JobReviewDetailScreen extends StatefulWidget {
  final String jobId;

  const JobReviewDetailScreen({
    super.key,
    required this.jobId,
  });

  @override
  State<JobReviewDetailScreen> createState() => _JobReviewDetailScreenState();
}

class _JobReviewDetailScreenState extends State<JobReviewDetailScreen> {
  final JobService _jobService = JobService();
  final PhotoService _photoService = PhotoService();
  final PDFService _pdfService = PDFService();
  SupabaseClient get _client => Supabase.instance.client;
  final ImagePicker _imagePicker = ImagePicker();

  String? _jobAddress;
  List<Map<String, dynamic>> _categories = [];
  Map<String, List<String>> _photosByCategory = {}; // Store download URLs
  Map<String, bool> _uploadingByCategory = {}; // Track upload state per category
  Map<String, bool> _deletingByPhoto = {}; // Track deletion state per photo
  bool _isLoading = true;
  bool _isApproving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Future.wait([
        _loadJobDetails(),
        _loadCategories(),
      ]);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load data: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadJobDetails() async {
    try {
      final job = await _jobService.getJobById(widget.jobId);
      setState(() {
        _jobAddress = job?['address'] as String?;
      });
    } catch (e) {
      print('Error loading job details: $e');
      setState(() {
        _errorMessage = 'Failed to load job details: ${e.toString()}';
      });
    }
  }

  Future<void> _loadCategories() async {
    try {
      final response = await _client
          .from('photo_categories')
          .select()
          .order('sort_order', ascending: true);

      final newCategories = List<Map<String, dynamic>>.from(response);

      setState(() {
        _categories = newCategories;
        // Initialize photo lists for each category
        for (var category in _categories) {
          final categoryId = category['id'].toString();
          _photosByCategory[categoryId] ??= [];
        }
      });

      // Load existing photos for each category
      await _loadExistingPhotos();
    } catch (e) {
      print('Error loading categories: $e');
      setState(() {
        _errorMessage = 'Failed to load categories: ${e.toString()}';
      });
    }
  }

  Future<void> _loadExistingPhotos() async {
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
        loadedPhotos[categoryId] = [];
      }
    }

    setState(() {
      _photosByCategory = loadedPhotos;
    });
  }

  Future<void> _addPhoto(String categoryId) async {
    // Show dialog to choose source
    final ImageSource? source = await showDialog<ImageSource>(
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

    if (source == null) return;

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _uploadingByCategory[categoryId] = true;
        });

        try {
          final bytes = await image.readAsBytes();
          final extension = image.name.split('.').last;

          // Find category name
          final category = _categories.firstWhere(
            (cat) => cat['id'].toString() == categoryId,
            orElse: () => {'name': 'Unknown'},
          );
          final categoryName = category['name'] as String? ?? 'Unknown';
          final address = _jobAddress ?? 'Unknown Address';

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

  Future<void> _deletePhoto(String categoryId, String photoUrl, int index) async {
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

    setState(() {
      _deletingByPhoto[photoUrl] = true;
    });

    try {
      await _photoService.deletePhoto(photoUrl, widget.jobId);

      // Remove from local state
      setState(() {
        _photosByCategory[categoryId]?.removeAt(index);
        _deletingByPhoto[photoUrl] = false;
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
      setState(() {
        _deletingByPhoto[photoUrl] = false;
      });
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

  Future<void> _generatePDF() async {
    try {
      print('[JobReviewDetailScreen] _generatePDF() - Starting PDF generation for job: ${widget.jobId}');
      
      // Collect all photo URLs from all categories
      final List<String> allPhotoUrls = [];
      for (var category in _categories) {
        final categoryId = category['id'].toString();
        final photos = _photosByCategory[categoryId] ?? [];
        allPhotoUrls.addAll(photos);
      }
      
      print('[JobReviewDetailScreen] _generatePDF() - Found ${allPhotoUrls.length} photos to include in PDF');
      
      if (_jobAddress == null || _jobAddress!.isEmpty) {
        throw Exception('Job address is required for PDF generation');
      }

      // Generate PDF
      print('[JobReviewDetailScreen] _generatePDF() - Calling PDFService.generateJobPDF()...');
      final pdfBytes = await _pdfService.generateJobPDF(
        widget.jobId,
        _jobAddress!,
        allPhotoUrls,
      );
      print('[JobReviewDetailScreen] _generatePDF() - PDF bytes generated, size: ${pdfBytes.length}');

      // Upload PDF to MinIO
      print('[JobReviewDetailScreen] _generatePDF() - Uploading PDF to MinIO Storage...');
      final pdfUrl = await _pdfService.savePDFToMinIO(widget.jobId, _jobAddress!, pdfBytes);
      print('[JobReviewDetailScreen] _generatePDF() - PDF uploaded to MinIO, URL: $pdfUrl');

      // Save PDF URL to Supabase jobs table
      print('[JobReviewDetailScreen] _generatePDF() - Saving PDF URL to Supabase jobs table...');
      await _client
          .from('jobs')
          .update({'pdf_url': pdfUrl})
          .eq('id', widget.jobId);
      print('[JobReviewDetailScreen] _generatePDF() - PDF URL saved to database: $pdfUrl');
    } catch (e, stackTrace) {
      print('[JobReviewDetailScreen] _generatePDF() - PDF generation error: $e\n$stackTrace');
      rethrow;
    }
  }

  Future<void> _approveAndGeneratePDF() async {
    if (_isApproving) return;

    setState(() {
      _isApproving = true;
    });

    String? errorStep;
    try {
      // Step 1: Generate PDF
      errorStep = 'PDF generation';
      print('[JobReviewDetailScreen] _approveAndGeneratePDF() - Step 1: Generating PDF...');
      await _generatePDF();

      // Step 2: Update job status to approved
      errorStep = 'Job approval';
      print('[JobReviewDetailScreen] _approveAndGeneratePDF() - Step 2: Updating job status to approved...');
      await _jobService.approveJob(widget.jobId);
      print('[JobReviewDetailScreen] _approveAndGeneratePDF() - Job approved successfully');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job approved and PDF generated successfully'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate back
        Navigator.of(context).pop(true);
      }
    } catch (e, stackTrace) {
      print('[JobReviewDetailScreen] _approveAndGeneratePDF() - PDF generation error: $e\n$stackTrace');
      if (mounted) {
        String errorMessage = 'Failed to approve job';
        if (errorStep != null) {
          errorMessage = 'Failed during $errorStep: ${e.toString()}';
        } else {
          errorMessage = 'Failed to approve job: ${e.toString()}';
        }
        
        // Show error in SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Details',
              textColor: Colors.white,
              onPressed: () {
                // Show detailed error dialog
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Error Details'),
                    content: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Text(
                        'Error: ${e.toString()}\n\nStack Trace:\n$stackTrace',
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isApproving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Review'),
        elevation: 2,
      ),
      body: _isLoading
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
                    // Job Address Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20.0),
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Job Address',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _jobAddress ?? 'N/A',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                          ),
                        ],
                      ),
                    ),

                    // Categories and Photos List
                    Expanded(
                      child: _categories.isEmpty
                          ? const Center(
                              child: Text('No photo categories found'),
                            )
                          : ListView.builder(
                              physics: const ClampingScrollPhysics(),
                              padding: const EdgeInsets.all(16.0),
                              itemCount: _categories.length,
                              itemBuilder: (context, index) {
                                final category = _categories[index];
                                final categoryId = category['id'].toString();
                                final categoryName =
                                    category['name'] as String? ?? 'Unnamed Category';
                                final photos = _photosByCategory[categoryId] ?? [];
                                final isUploading = _uploadingByCategory[categoryId] == true;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 24.0),
                                  elevation: 2,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Category Header
                                        Text(
                                          categoryName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 16),

                                        // Photo Grid
                                        if (photos.isNotEmpty)
                                          LayoutBuilder(
                                            builder: (context, constraints) {
                                              // Calculate number of columns based on screen width
                                              final crossAxisCount = constraints.maxWidth > 600
                                                  ? 3
                                                  : constraints.maxWidth > 400
                                                      ? 2
                                                      : 2;

                                              return GridView.builder(
                                                shrinkWrap: true,
                                                physics: const NeverScrollableScrollPhysics(),
                                                gridDelegate:
                                                    SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: crossAxisCount,
                                                  crossAxisSpacing: 8,
                                                  mainAxisSpacing: 8,
                                                  childAspectRatio: 1,
                                                ),
                                                itemCount: photos.length,
                                                itemBuilder: (context, photoIndex) {
                                                  final photoUrl = photos[photoIndex];
                                                  final isDeleting =
                                                      _deletingByPhoto[photoUrl] == true;

                                                  return Stack(
                                                    children: [
                                                      Container(
                                                        decoration: BoxDecoration(
                                                          borderRadius: BorderRadius.circular(8),
                                                          border: Border.all(
                                                            color: Colors.grey[300]!,
                                                          ),
                                                        ),
                                                        child: ClipRRect(
                                                          borderRadius: BorderRadius.circular(8),
                                                          child: isDeleting
                                                              ? Container(
                                                                  color: Colors.grey[200],
                                                                  child: const Center(
                                                                    child:
                                                                        CircularProgressIndicator(),
                                                                  ),
                                                                )
                                                              : Image.network(
                                                                  photoUrl,
                                                                  fit: BoxFit.cover,
                                                                  loadingBuilder: (context, child,
                                                                      loadingProgress) {
                                                                    if (loadingProgress == null) {
                                                                      return child;
                                                                    }
                                                                    return Center(
                                                                      child:
                                                                          CircularProgressIndicator(
                                                                        value: loadingProgress
                                                                                    .expectedTotalBytes !=
                                                                                null
                                                                            ? loadingProgress
                                                                                    .cumulativeBytesLoaded /
                                                                                loadingProgress
                                                                                    .expectedTotalBytes!
                                                                            : null,
                                                                      ),
                                                                    );
                                                                  },
                                                                  errorBuilder:
                                                                      (context, error, stackTrace) {
                                                                    return Container(
                                                                      color: Colors.grey[200],
                                                                      child: const Icon(
                                                                        Icons.error,
                                                                        color: Colors.red,
                                                                      ),
                                                                    );
                                                                  },
                                                                ),
                                                        ),
                                                      ),
                                                      if (!isDeleting)
                                                        Positioned(
                                                          top: 4,
                                                          right: 4,
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
                                                            onPressed: () => _deletePhoto(
                                                                categoryId, photoUrl, photoIndex),
                                                            padding: EdgeInsets.zero,
                                                            constraints: const BoxConstraints(),
                                                          ),
                                                        ),
                                                    ],
                                                  );
                                                },
                                              );
                                            },
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

                                        const SizedBox(height: 16),

                                        // Add Photo Button
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            onPressed: isUploading
                                                ? null
                                                : () => _addPhoto(categoryId),
                                            icon: isUploading
                                                ? const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child: CircularProgressIndicator(strokeWidth: 2),
                                                  )
                                                : const Icon(Icons.add_photo_alternate),
                                            label: Text(
                                              isUploading ? 'Uploading...' : 'Add Photo',
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(vertical: 12),
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

                    // Approve & Generate PDF Button (Fixed at bottom)
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
                          child: ElevatedButton.icon(
                            onPressed: _isApproving ? null : _approveAndGeneratePDF,
                            icon: _isApproving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_circle),
                            label: Text(_isApproving ? 'Processing...' : 'Approve & Generate PDF'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey[300],
                              disabledForegroundColor: Colors.grey[600],
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
