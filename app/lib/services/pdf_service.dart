import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:minio/minio.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PDFService {
  // MinIO configuration
  static const String _minioEndpoint = 'minio-api.entify.ca';
  static const String _bucket = 'hudson-photos';
  static const bool _useSSL = true;
  static const String _baseUrl = 'https://minio-api.entify.ca/hudson-photos';
  
  late final Minio _minio;
  
  PDFService() {
    // Try to get from dotenv first (for local development)
    String accessKey = dotenv.env['MINIO_ACCESS_KEY'] ?? '';
    String secretKey = dotenv.env['MINIO_SECRET_KEY'] ?? '';
    
    // For web deployments, also check if they're set via environment variables
    // that might be injected at build time (e.g., via --dart-define)
    if (accessKey.isEmpty) {
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
    
    _minio = Minio(
      endPoint: _minioEndpoint,
      accessKey: accessKey,
      secretKey: secretKey,
      useSSL: _useSSL,
    );
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

  /// Generates a PDF document for a job with address and photos
  /// 
  /// [jobId] - The ID of the job
  /// [address] - The job address to display at the top
  /// [photoUrls] - List of photo URLs to include in the PDF
  /// Returns the PDF as Uint8List bytes
  Future<Uint8List> generateJobPDF(
    String jobId,
    String address,
    List<String> photoUrls,
  ) async {
    try {
      print('[PDFService] generateJobPDF() - Generating PDF for job: $jobId');

      final pdf = pw.Document();

      // Download and convert photos to PDF images with dimensions
      final List<Map<String, dynamic>> photoData = [];
      
      for (var photoUrl in photoUrls) {
        try {
          print('[PDFService] generateJobPDF() - Downloading photo: $photoUrl');
          final response = await http.get(Uri.parse(photoUrl));
          
          if (response.statusCode == 200) {
            final imageBytes = response.bodyBytes;
            final image = pw.MemoryImage(imageBytes);
            
            // Decode image to get dimensions for aspect ratio
            final codec = await ui.instantiateImageCodec(imageBytes);
            final frame = await codec.getNextFrame();
            final imageInfo = frame.image;
            final width = imageInfo.width.toDouble();
            final height = imageInfo.height.toDouble();
            imageInfo.dispose();
            
            photoData.add({
              'image': image,
              'width': width,
              'height': height,
            });
            print('[PDFService] generateJobPDF() - Photo downloaded successfully (${width.toInt()}x${height.toInt()})');
          } else {
            print('[PDFService] generateJobPDF() - Failed to download photo: ${response.statusCode}');
          }
        } catch (e) {
          print('[PDFService] generateJobPDF() - Error downloading photo $photoUrl: $e');
          // Continue with other photos even if one fails
        }
      }

      // Calculate available width (A4 width - margins)
      // A4: 595 points wide, 40pt margins on each side = 515 points available
      const double photoWidth = 450; // Large, audit-quality size
      
      // Build PDF content
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            final List<pw.Widget> widgets = [
              // Job Address Header
              pw.Text(
                address,
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 20),
            ];
            
            // Add photos one per row, maintaining aspect ratio
            if (photoData.isNotEmpty) {
              for (var photo in photoData) {
                final image = photo['image'] as pw.ImageProvider;
                final originalWidth = photo['width'] as double;
                final originalHeight = photo['height'] as double;
                
                // Calculate height to maintain aspect ratio
                final aspectRatio = originalHeight / originalWidth;
                final photoHeight = photoWidth * aspectRatio;
                
                widgets.add(
                  pw.Container(
                    width: photoWidth,
                    height: photoHeight,
                    child: pw.Image(
                      image,
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                );
                widgets.add(pw.SizedBox(height: 20)); // Spacing between photos
              }
            } else {
              widgets.add(
                pw.Text(
                  'No photos available',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              );
            }
            
            return widgets;
          },
        ),
      );

      // Generate PDF bytes
      final pdfBytes = await pdf.save();
      print('[PDFService] generateJobPDF() - PDF generated successfully, size: ${pdfBytes.length} bytes');
      
      return pdfBytes;
    } catch (e) {
      print('[PDFService] generateJobPDF() - Error: $e');
      rethrow;
    }
  }

  /// Saves a PDF to MinIO Storage
  /// 
  /// [jobId] - The ID of the job
  /// [address] - The job address (for path structure)
  /// [pdfBytes] - The PDF file as Uint8List bytes
  /// Returns the download URL of the uploaded PDF
  Future<String> savePDFToMinIO(
    String jobId,
    String address,
    Uint8List pdfBytes,
  ) async {
    try {
      print('[PDFService] savePDFToMinIO() - Uploading PDF for job: $jobId');

      // Build path with sanitized address and job ID
      final sanitizedAddress = _sanitizeForPath(address);
      final shortJobId = jobId.length > 8 ? jobId.substring(0, 8) : jobId;
      final objectPath = 'jobs/${sanitizedAddress}_$shortJobId/${sanitizedAddress}_$shortJobId.pdf';

      print('[PDFService] savePDFToMinIO() - MinIO object path: $objectPath');

      // Convert bytes to stream for S3-compatible API
      final stream = Stream<Uint8List>.value(pdfBytes);
      
      // Upload to MinIO Storage
      await _minio.putObject(
        _bucket,
        objectPath,
        stream,
        size: pdfBytes.length,
        metadata: {'Content-Type': 'application/pdf'},
      );

      // Generate public URL
      final downloadUrl = '$_baseUrl/$objectPath';
      print('[PDFService] savePDFToMinIO() - PDF uploaded successfully: $downloadUrl');
      
      return downloadUrl;
    } catch (e) {
      print('[PDFService] savePDFToMinIO() - Error: $e');
      rethrow;
    }
  }
}
