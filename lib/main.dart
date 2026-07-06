import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'core/theme/app_theme.dart';
import 'features/configuration/data/repositories/configuration_repository_impl.dart';
import 'features/configuration/presentation/providers/config_provider.dart';
import 'features/drive/data/datasources/drive_remote_data_source.dart';
import 'features/drive/data/repositories/drive_repository_impl.dart';
import 'features/drive/presentation/providers/drive_provider.dart';
import 'features/dashboard/presentation/screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final sharedPrefs = await SharedPreferences.getInstance();
  final configRepository = ConfigurationRepositoryImpl(sharedPrefs);
  
  final httpClient = http.Client();
  final driveDataSource = DriveRemoteDataSource(httpClient);
  final driveRepository = DriveRepositoryImpl(driveDataSource);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ConfigProvider>(
          create: (_) => ConfigProvider(configRepository),
        ),
        ChangeNotifierProvider<DriveProvider>(
          create: (_) => DriveProvider(driveRepository),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GDrive Stream Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const DashboardScreen(),
    );
  }
}
