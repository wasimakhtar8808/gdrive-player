import 'package:shared_preferences/shared_preferences.dart';

class PlaybackTracker {
  static const String _prefix = 'video_resume_pos_';

  static Future<int> getPosition(String videoId) async {
    if (videoId.trim().isEmpty) return 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('$_prefix$videoId') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> savePosition(String videoId, int positionInSeconds) async {
    if (videoId.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('$_prefix$videoId', positionInSeconds);
    } catch (_) {}
  }

  static Future<void> clearPosition(String videoId) async {
    if (videoId.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$videoId');
    } catch (_) {}
  }
}
