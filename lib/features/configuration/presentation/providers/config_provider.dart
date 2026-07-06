import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import '../../domain/entities/token_entity.dart';
import '../../domain/repositories/configuration_repository.dart';

enum ConnectionStatus { idle, testing, connected, failed }

class ConfigProvider with ChangeNotifier {
  final ConfigurationRepository _repository;

  ConfigProvider(this._repository) {
    _init();
  }

  TokenEntity _tokens = const TokenEntity.empty();
  bool _isLoading = true;
  ConnectionStatus _connectionStatus = ConnectionStatus.idle;
  String _errorMessage = '';
  GoogleSignInAccount? _googleAccount;
  bool _isListenerRegistered = false;

  TokenEntity get tokens => _tokens;
  bool get isLoading => _isLoading;
  ConnectionStatus get connectionStatus => _connectionStatus;
  String get errorMessage => _errorMessage;
  GoogleSignInAccount? get googleAccount => _googleAccount;
  bool get isGoogleSignedIn => _googleAccount != null;

  Future<void> _init() async {
    _tokens = await _repository.loadTokens();

    // If client ID is already saved, silently authenticate to recover session
    if (_tokens.hasClientId) {
      try {
        await GoogleSignIn.instance.initialize(serverClientId: _tokens.serverClientId);
        _setupGoogleSignInListener();
        await GoogleSignIn.instance.attemptLightweightAuthentication();
      } catch (_) {
        // Ignore initialization errors on boot
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  void _setupGoogleSignInListener() {
    if (_isListenerRegistered) return;
    
    GoogleSignIn.instance.authenticationEvents.listen((event) async {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        _googleAccount = event.user;
        final scopes = ['https://www.googleapis.com/auth/drive.readonly'];
        
        try {
          var auth = await _googleAccount!.authorizationClient.authorizationForScopes(scopes);
          auth ??= await _googleAccount!.authorizationClient.authorizeScopes(scopes);
          final accessToken = auth.accessToken;
          
          if (accessToken.isNotEmpty) {
            _tokens = _tokens.copyWith(accessToken: accessToken);
            await _repository.saveTokens(_tokens);
            _connectionStatus = ConnectionStatus.connected;
            notifyListeners();
          }
        } catch (_) {
          // Error fetching scopes in background stream listener
        }
      } else if (event is GoogleSignInAuthenticationEventSignOut) {
        _googleAccount = null;
        await clearConfig();
      }
    });

    _isListenerRegistered = true;
  }

  Future<void> saveConfig(String apiKey, String accessToken, String serverClientId) async {
    _isLoading = true;
    _connectionStatus = ConnectionStatus.idle;
    _errorMessage = '';
    notifyListeners();

    _tokens = TokenEntity(
      apiKey: apiKey,
      accessToken: accessToken,
      serverClientId: serverClientId,
    );
    await _repository.saveTokens(_tokens);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> clearConfig() async {
    _isLoading = true;
    notifyListeners();

    await _repository.clearTokens();
    _tokens = const TokenEntity.empty();
    _connectionStatus = ConnectionStatus.idle;
    _errorMessage = '';
    _googleAccount = null;
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> signInWithGoogle() async {
    if (!_tokens.hasClientId) {
      _connectionStatus = ConnectionStatus.failed;
      _errorMessage = 'Google OAuth Client ID must be configured in Settings first.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _connectionStatus = ConnectionStatus.testing;
    _errorMessage = '';
    notifyListeners();

    try {
      // Re-initialize to ensure it uses the latest client ID configuration
      await GoogleSignIn.instance.initialize(serverClientId: _tokens.serverClientId);
      _setupGoogleSignInListener();

      final GoogleSignInAccount? account = await GoogleSignIn.instance.authenticate();
      if (account != null) {
        final scopes = ['https://www.googleapis.com/auth/drive.readonly'];
        
        var auth = await account.authorizationClient.authorizationForScopes(scopes);
        auth ??= await account.authorizationClient.authorizeScopes(scopes);

        final accessToken = auth.accessToken;

        _tokens = _tokens.copyWith(accessToken: accessToken);
        await _repository.saveTokens(_tokens);

        _googleAccount = account;
        _connectionStatus = ConnectionStatus.connected;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _connectionStatus = ConnectionStatus.failed;
        _errorMessage = 'Sign in cancelled by user.';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _connectionStatus = ConnectionStatus.failed;
      _errorMessage = 'Sign in failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOutGoogle() async {
    _isLoading = true;
    notifyListeners();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    _googleAccount = null;
    await clearConfig();
  }

  Future<bool> testConnection() async {
    if (_tokens.isEmpty) {
      _connectionStatus = ConnectionStatus.failed;
      _errorMessage = 'API Key, Access Token and Client ID are empty.';
      notifyListeners();
      return false;
    }

    _connectionStatus = ConnectionStatus.testing;
    _errorMessage = '';
    notifyListeners();

    try {
      final Uri uri;
      final Map<String, String> headers = {};

      if (_tokens.hasAccessToken) {
        uri = Uri.parse('https://www.googleapis.com/drive/v3/files?pageSize=1');
        headers['Authorization'] = 'Bearer ${_tokens.accessToken}';
      } else {
        uri = Uri.parse('https://www.googleapis.com/drive/v3/files?pageSize=1&key=${_tokens.apiKey}');
      }

      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _connectionStatus = ConnectionStatus.connected;
        notifyListeners();
        return true;
      } else {
        _connectionStatus = ConnectionStatus.failed;
        try {
          final body = json.decode(response.body);
          _errorMessage = body['error']['message'] ?? 'Failed with status code ${response.statusCode}';
        } catch (_) {
          _errorMessage = 'Failed with status code ${response.statusCode}';
        }
        notifyListeners();
        return false;
      }
    } catch (e) {
      _connectionStatus = ConnectionStatus.failed;
      _errorMessage = 'Connection failed: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }
}
