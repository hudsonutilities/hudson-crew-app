import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';

class JobService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Gets the active job from the jobs table
  /// Returns the job data as a Map, or null if no active job exists
  Future<Map<String, dynamic>?> getActiveJob() async {
    try {
      print('[JobService] getActiveJob() - Querying for active job...');
      final response = await _client
          .from('jobs')
          .select()
          .eq('status', 'active')
          .maybeSingle();

      print('[JobService] getActiveJob() - Query result: $response');
      return response;
    } catch (e) {
      print('[JobService] getActiveJob() - Error: $e');
      rethrow;
    }
  }

  /// Creates a new job with the given address
  /// Sets status to 'active'
  /// Returns the created job ID
  Future<String> createJob(String address) async {
    try {
      print('[JobService] createJob() - Creating job with address: $address');
      final response = await _client
          .from('jobs')
          .insert({
            'address': address,
            'status': 'active',
          })
          .select()
          .single();

      print('[JobService] createJob() - Supabase response: $response');
      final jobId = response['id'] as String;
      print('[JobService] createJob() - Created job with ID: $jobId');
      return jobId;
    } catch (e) {
      print('[JobService] createJob() - Error: $e');
      rethrow;
    }
  }

  /// Completes a job by updating its status to 'pending_review'
  /// Takes the job ID as parameter
  Future<void> completeJob(String jobId) async {
    try {
      print('[JobService] completeJob() - Completing job with ID: $jobId');
      await _client
          .from('jobs')
          .update({'status': 'pending_review'})
          .eq('id', jobId);
      print('[JobService] completeJob() - Job $jobId completed successfully');
    } catch (e) {
      print('[JobService] completeJob() - Error: $e');
      rethrow;
    }
  }

  /// Gets all jobs with status 'pending_review' or 'approved', ordered by most recent first
  /// Returns a list of job data as Maps
  Future<List<Map<String, dynamic>>> getPendingReviewJobs() async {
    try {
      print('[JobService] getPendingReviewJobs() - Querying for pending review and approved jobs...');
      final response = await _client
          .from('jobs')
          .select()
          .or('status.eq.pending_review,status.eq.approved')
          .order('created_at', ascending: false);

      print('[JobService] getPendingReviewJobs() - Query result: $response');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('[JobService] getPendingReviewJobs() - Error: $e');
      rethrow;
    }
  }

  /// Gets a job by ID
  /// Returns the job data as a Map, or null if not found
  Future<Map<String, dynamic>?> getJobById(String jobId) async {
    try {
      print('[JobService] getJobById() - Querying for job: $jobId');
      final response = await _client
          .from('jobs')
          .select()
          .eq('id', jobId)
          .maybeSingle();

      print('[JobService] getJobById() - Query result: $response');
      return response;
    } catch (e) {
      print('[JobService] getJobById() - Error: $e');
      rethrow;
    }
  }

  /// Approves a job by updating its status to 'approved'
  /// Takes the job ID as parameter
  Future<void> approveJob(String jobId) async {
    try {
      print('[JobService] approveJob() - Approving job with ID: $jobId');
      await _client
          .from('jobs')
          .update({'status': 'approved'})
          .eq('id', jobId);
      print('[JobService] approveJob() - Job $jobId approved successfully');
    } catch (e) {
      print('[JobService] approveJob() - Error: $e');
      rethrow;
    }
  }

  /// Marks a job as complete by updating its status to 'completed'
  /// Takes the job ID as parameter
  Future<void> markJobComplete(String jobId) async {
    try {
      print('[JobService] markJobComplete() - Marking job as complete: $jobId');
      await _client
          .from('jobs')
          .update({'status': 'completed'})
          .eq('id', jobId);
      print('[JobService] markJobComplete() - Job $jobId marked as complete successfully');
    } catch (e) {
      print('[JobService] markJobComplete() - Error: $e');
      rethrow;
    }
  }

  /// Undoes job approval by updating status to 'pending_review' and clearing pdf_url
  /// Takes the job ID as parameter
  Future<void> undoApproval(String jobId) async {
    try {
      print('[JobService] undoApproval() - Undoing approval for job: $jobId');
      await _client
          .from('jobs')
          .update({
            'status': 'pending_review',
            'pdf_url': null,
          })
          .eq('id', jobId);
      print('[JobService] undoApproval() - Job $jobId approval undone successfully');
    } catch (e) {
      print('[JobService] undoApproval() - Error: $e');
      rethrow;
    }
  }
}
