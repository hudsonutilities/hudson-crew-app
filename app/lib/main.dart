import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'config/app_config.dart';
import 'screens/job_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  // Try to load .env.local, but don't fail if it doesn't exist (for web deployments)
  try {
    await dotenv.load(fileName: '.env.local');
  } catch (e) {
    // For web deployments, environment variables may be set via build-time injection
    // or through the deployment platform's environment variables
    print('Warning: Could not load .env.local: $e');
    print('Make sure MINIO_ACCESS_KEY and MINIO_SECRET_KEY are set in your deployment environment');
  }

  // Initialize Supabase
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  runApp(const MyApp());
}

class NoBouncingScrollBehavior extends MaterialScrollBehavior {
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hudson Crew App',
      scrollBehavior: NoBouncingScrollBehavior(),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const JobScreen(),
    );
  }
}

