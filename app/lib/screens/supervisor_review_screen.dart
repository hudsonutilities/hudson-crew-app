import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/job_service.dart';
import '../services/photo_service.dart';
import 'job_review_detail_screen.dart';

class SupervisorReviewScreen extends StatefulWidget {
  const SupervisorReviewScreen({super.key});

  @override
  State<SupervisorReviewScreen> createState() => _SupervisorReviewScreenState();
}

class _SupervisorReviewScreenState extends State<SupervisorReviewScreen> {
  final JobService _jobService = JobService();
  final PhotoService _photoService = PhotoService();
  Future<List<Map<String, dynamic>>>? _jobsFuture;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  void _loadJobs() {
    setState(() {
      _jobsFuture = _jobService.getPendingReviewJobs();
    });
  }

  Future<int> _getPhotoCount(String jobId) async {
    try {
      return await _photoService.getPhotoCountForJob(jobId);
    } catch (e) {
      print('Error getting photo count: $e');
      return 0;
    }
  }

  Future<void> _downloadPDF(String pdfUrl) async {
    try {
      final uri = Uri.parse(pdfUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open PDF URL'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening PDF: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _markJobComplete(String jobId) async {
    try {
      await _jobService.markJobComplete(jobId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job marked as complete'),
            backgroundColor: Colors.green,
          ),
        );
        // Refresh the list
        _loadJobs();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to mark job as complete: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _undoApproval(String jobId) async {
    try {
      await _jobService.undoApproval(jobId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job approval undone'),
            backgroundColor: Colors.orange,
          ),
        );
        // Refresh the list
        _loadJobs();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to undo approval: ${e.toString()}'),
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
        title: const Text('Pending Reviews'),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadJobs,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _jobsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red[300],
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Text(
                      'Error loading jobs: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red[700]),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _loadJobs,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final jobs = snapshot.data ?? [];

          if (jobs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No jobs pending review',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'All jobs have been reviewed',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[500],
                        ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              _loadJobs();
              // Wait for the future to complete
              await _jobsFuture;
            },
            child: ListView.builder(
              primary: true,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              itemCount: jobs.length,
              itemBuilder: (context, index) {
                final job = jobs[index];
                final jobId = job['id']?.toString() ?? '';
                final address = job['address'] as String? ?? 'N/A';
                final status = job['status'] as String? ?? '';
                final pdfUrl = job['pdf_url'] as String?;
                final isApproved = status == 'approved';
                final isPendingReview = status == 'pending_review';

                return Card(
                  margin: const EdgeInsets.only(bottom: 16.0),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Address and Status Badge
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                address,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ),
                            if (isApproved) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Approved',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.undo, size: 20),
                                onPressed: () => _undoApproval(jobId),
                                tooltip: 'Undo Approval',
                                color: Colors.orange,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Photo count
                        Row(
                          children: [
                            Icon(
                              Icons.photo_library,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            FutureBuilder<int>(
                              future: _getPhotoCount(jobId),
                              builder: (context, photoSnapshot) {
                                final count = photoSnapshot.data ?? 0;
                                return Text(
                                  '$count ${count == 1 ? 'photo' : 'photos'}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Action buttons based on status
                        if (isPendingReview)
                          // Review button for pending_review
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => JobReviewDetailScreen(
                                      jobId: jobId,
                                    ),
                                  ),
                                ).then((_) {
                                  // Refresh list when returning from detail screen
                                  _loadJobs();
                                });
                              },
                              icon: const Icon(Icons.reviews),
                              label: const Text('Review'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          )
                        else if (isApproved)
                          // Buttons for approved jobs
                          Column(
                            children: [
                              // Download PDF button
                              if (pdfUrl != null && pdfUrl.isNotEmpty)
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _downloadPDF(pdfUrl),
                                    icon: const Icon(Icons.download),
                                    label: const Text('Download PDF'),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'PDF not available',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              // Mark Complete button
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => _markJobComplete(jobId),
                                  icon: const Icon(Icons.check_circle),
                                  label: const Text('Mark Complete'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
