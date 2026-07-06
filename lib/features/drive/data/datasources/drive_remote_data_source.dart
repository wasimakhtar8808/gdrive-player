import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../configuration/domain/entities/token_entity.dart';
import '../../domain/entities/drive_item.dart';
import '../../../../core/errors/exceptions.dart';

class DriveRemoteDataSource {
  final http.Client _client;

  DriveRemoteDataSource(this._client);

  Future<List<DriveItem>> fetchFiles({
    required String folderId,
    required TokenEntity token,
  }) async {
    if (token.isEmpty) {
      throw AuthException('API Key or Access Token is required to browse Google Drive.');
    }

    final targetFolder = folderId.isEmpty ? 'root' : folderId;
    final query = "trashed = false and '$targetFolder' in parents and (mimeType = 'application/vnd.google-apps.folder' or mimeType starts with 'video/')";
    
    return _executeRequest(query: query, token: token);
  }

  Future<List<DriveItem>> searchFiles({
    required String searchPattern,
    required TokenEntity token,
  }) async {
    if (token.isEmpty) {
      throw AuthException('API Key or Access Token is required to search Google Drive.');
    }

    // Escape search pattern single quotes
    final escapedPattern = searchPattern.replaceAll("'", "\\'");
    final query = "trashed = false and name contains '$escapedPattern' and (mimeType = 'application/vnd.google-apps.folder' or mimeType starts with 'video/')";

    return _executeRequest(query: query, token: token);
  }

  Future<List<DriveItem>> _executeRequest({
    required String query,
    required TokenEntity token,
  }) async {
    final Map<String, String> headers = {};
    final Uri uri;

    final queryParams = {
      'q': query,
      'fields': 'files(id, name, mimeType, size, modifiedTime, thumbnailLink)',
    };

    if (token.hasAccessToken) {
      headers['Authorization'] = 'Bearer ${token.accessToken}';
      uri = Uri.https('www.googleapis.com', '/drive/v3/files', queryParams);
    } else {
      queryParams['key'] = token.apiKey;
      uri = Uri.https('www.googleapis.com', '/drive/v3/files', queryParams);
    }

    try {
      final response = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final List<dynamic> filesJson = body['files'] ?? [];
        
        final List<DriveItem> items = filesJson
            .map((json) => DriveItem.fromJson(json))
            .toList();

        // Sort: Folders first, then alphabetically by name
        items.sort((a, b) {
          if (a.isFolder && !b.isFolder) return -1;
          if (!a.isFolder && b.isFolder) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

        return items;
      } else {
        String errorMsg = 'Failed to load drive files.';
        try {
          final body = json.decode(response.body);
          errorMsg = body['error']['message'] ?? errorMsg;
        } catch (_) {}
        
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw AuthException('Authentication failed: $errorMsg');
        } else {
          throw ServerException(errorMsg);
        }
      }
    } catch (e) {
      if (e is AuthException || e is ServerException) {
        rethrow;
      }
      throw NetworkException('Network connection failed. Please check your network.');
    }
  }
}
