import 'package:flutter/material.dart';
import '../services/job_service.dart';
import 'photo_upload_screen.dart';
import 'supervisor_review_screen.dart';

class JobScreen extends StatefulWidget {
  const JobScreen({super.key});

  @override
  State<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends State<JobScreen> {
  final JobService _jobService = JobService();
  Map<String, dynamic>? _activeJob;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadActiveJob();
  }

  Future<void> _loadActiveJob() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final job = await _jobService.getActiveJob();
      setState(() {
        _activeJob = job;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load job: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _startNewJob() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final TextEditingController addressController = TextEditingController();
        bool isSubmitting = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Start New Job'),
              content: TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  hintText: 'Enter job address',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
                enabled: !isSubmitting,
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          Navigator.of(context).pop();
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (addressController.text.trim().isNotEmpty) {
                            setDialogState(() {
                              isSubmitting = true;
                            });

                            try {
                              await _jobService.createJob(
                                addressController.text.trim(),
                              );
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                await _loadActiveJob();
                              }
                            } catch (e) {
                              setDialogState(() {
                                isSubmitting = false;
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Failed to create job: ${e.toString()}',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Start'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _navigateToPhotoUpload() {
    if (_activeJob == null || _activeJob!['id'] == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhotoUploadScreen(
          jobId: _activeJob!['id'] as String,
          readOnly: false,
        ),
      ),
    ).then((_) {
      // Reload job when returning from photo screen
      // If job was submitted for review, it will no longer appear (status changed to pending_review)
      _loadActiveJob();
    });
  }

  void _navigateToSupervisorReview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SupervisorReviewScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jobs'),
        elevation: 2,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Error Message
                  if (_errorMessage != null)
                    Card(
                      color: Colors.red[50],
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red[700]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(color: Colors.red[700]),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                setState(() {
                                  _errorMessage = null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_errorMessage != null) const SizedBox(height: 16),
                  // Job Section
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Active Job',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 12),
                          if (_activeJob != null)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Address:',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _activeJob!['address'] as String? ?? 'N/A',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ],
                            )
                          else
                            Text(
                              'No active job',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Action Buttons
                  if (_activeJob == null)
                    ElevatedButton.icon(
                      onPressed: _startNewJob,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Start New Job'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: _navigateToPhotoUpload,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('View/Upload Photos'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  const SizedBox(height: 32),
                  // Supervisor Review Button
                  OutlinedButton.icon(
                    onPressed: _navigateToSupervisorReview,
                    icon: const Icon(Icons.rate_review),
                    label: const Text('Review Jobs'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
