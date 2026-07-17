import 'package:flutter/material.dart';
import '../../../configuration/domain/entities/token_entity.dart';
import '../../domain/entities/drive_item.dart';
import '../../domain/repositories/drive_repository.dart';
import '../../../../core/errors/failures.dart';

class FolderBreadcrumb {
  final String id;
  final String name;

  FolderBreadcrumb({required this.id, required this.name});
}

class StreamSource {
  final String url;
  final Map<String, String> headers;
  final String title;

  StreamSource({
    required this.url,
    required this.headers,
    required this.title,
  });
}

class DriveProvider with ChangeNotifier {
  final DriveRepository _repository;

  DriveProvider(this._repository);

  List<DriveItem> _items = [];
  bool _isLoading = false;
  String _errorMessage = '';
  bool _isGridView = false;
  
  final List<FolderBreadcrumb> _breadcrumbs = [
    FolderBreadcrumb(id: 'root', name: 'My Drive')
  ];

  List<DriveItem> get items => _items;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  bool get isGridView => _isGridView;
  List<FolderBreadcrumb> get breadcrumbs => _breadcrumbs;
  
  String get currentFolderId => _breadcrumbs.last.id;
  String get currentFolderName => _breadcrumbs.last.name;

  void toggleViewMode() {
    _isGridView = !_isGridView;
    notifyListeners();
  }

  Future<void> loadCurrentFolder(
    TokenEntity token, {
    Future<TokenEntity?> Function()? onAuthError,
  }) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final results = await _repository.getDriveContents(
        folderId: currentFolderId,
        token: token,
      );
      _items = results;
    } catch (e) {
      if (e is AuthFailure && onAuthError != null) {
        final newToken = await onAuthError();
        if (newToken != null) {
          try {
            final results = await _repository.getDriveContents(
              folderId: currentFolderId,
              token: newToken,
            );
            _items = results;
            return;
          } catch (retryException) {
            _errorMessage = retryException.toString();
            _items = [];
          }
        } else {
          _errorMessage = 'Session expired. Please sign in again.';
          _items = [];
        }
      } else {
        _errorMessage = e.toString();
        _items = [];
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> navigateToFolder(
    DriveItem folder,
    TokenEntity token, {
    Future<TokenEntity?> Function()? onAuthError,
  }) async {
    if (!folder.isFolder) return;
    
    _breadcrumbs.add(FolderBreadcrumb(id: folder.id, name: folder.name));
    await loadCurrentFolder(token, onAuthError: onAuthError);
  }

  Future<void> navigateToBreadcrumbIndex(
    int index,
    TokenEntity token, {
    Future<TokenEntity?> Function()? onAuthError,
  }) async {
    if (index < 0 || index >= _breadcrumbs.length) return;
    
    // Remove all levels after this index
    _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
    await loadCurrentFolder(token, onAuthError: onAuthError);
  }

  Future<void> navigateBack(
    TokenEntity token, {
    Future<TokenEntity?> Function()? onAuthError,
  }) async {
    if (_breadcrumbs.length > 1) {
      _breadcrumbs.removeLast();
      await loadCurrentFolder(token, onAuthError: onAuthError);
    }
  }

  Future<void> search(
    String query,
    TokenEntity token, {
    Future<TokenEntity?> Function()? onAuthError,
  }) async {
    if (query.trim().isEmpty) {
      await loadCurrentFolder(token, onAuthError: onAuthError);
      return;
    }

    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final results = await _repository.searchDrive(
        query: query,
        token: token,
      );
      _items = results;
    } catch (e) {
      if (e is AuthFailure && onAuthError != null) {
        final newToken = await onAuthError();
        if (newToken != null) {
          try {
            final results = await _repository.searchDrive(
              query: query,
              token: newToken,
            );
            _items = results;
            return;
          } catch (retryException) {
            _errorMessage = retryException.toString();
            _items = [];
          }
        } else {
          _errorMessage = 'Session expired. Please sign in again.';
          _items = [];
        }
      } else {
        _errorMessage = e.toString();
        _items = [];
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  StreamSource getStreamSource(DriveItem item, TokenEntity token) {
    final Map<String, String> headers = {};
    String url;

    if (token.hasAccessToken) {
      url = 'https://www.googleapis.com/drive/v3/files/${item.id}?alt=media&access_token=${token.accessToken}';
    } else {
      url = 'https://www.googleapis.com/drive/v3/files/${item.id}?alt=media&key=${token.apiKey}';
    }

    return StreamSource(
      url: url,
      headers: headers,
      title: item.name,
    );
  }
}
