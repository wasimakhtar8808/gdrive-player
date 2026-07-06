import 'package:flutter/material.dart';
import 'package:gdrive_player/features/drive/presentation/screens/drive_browser_screen.dart';
import 'package:gdrive_player/features/player/presentation/screens/live_stream_screen.dart';
import 'package:gdrive_player/features/configuration/presentation/screens/settings_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 3,
      child: Scaffold(
        body: TabBarView(
          physics: NeverScrollableScrollPhysics(), // Prevent swipe switching to avoid conflict with players
          children: [
            DriveBrowserScreen(),
            LiveStreamScreen(),
            SettingsScreen(),
          ],
        ),
        bottomNavigationBar: Material(
          color: Color(0xFF161B22),
          child: TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.cloud_queue),
                text: 'Drive',
              ),
              Tab(
                icon: Icon(Icons.stream),
                text: 'Stream',
              ),
              Tab(
                icon: Icon(Icons.settings),
                text: 'Settings',
              ),
            ],
            indicatorColor: Colors.orange,
            labelColor: Colors.orange,
            unselectedLabelColor: Colors.grey,
            labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            indicatorSize: TabBarIndicatorSize.tab,
          ),
        ),
      ),
    );
  }
}
