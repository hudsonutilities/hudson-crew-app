import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PDFService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

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

  /// Saves a PDF to Firebase Storage
  /// 
  /// [jobId] - The ID of the job
  /// [pdfBytes] - The PDF file as Uint8List bytes
  /// Returns the download URL of the uploaded PDF
  Future<String> savePDFToFirebase(String jobId, Uint8List pdfBytes) async {
    try {
      print('[PDFService] savePDFToFirebase() - Uploading PDF for job: $jobId');

      final storageRef = _storage.ref().child('pdfs/$jobId.pdf');
      
      await storageRef.putData(
        pdfBytes,
        SettableMetadata(contentType: 'application/pdf'),
      );

      final downloadUrl = await storageRef.getDownloadURL();
      print('[PDFService] savePDFToFirebase() - PDF uploaded successfully: $downloadUrl');
      
      return downloadUrl;
    } catch (e) {
      print('[PDFService] savePDFToFirebase() - Error: $e');
      rethrow;
    }
  }
}
