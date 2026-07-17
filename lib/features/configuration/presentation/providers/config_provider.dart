import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  User? _firebaseUser;

  TokenEntity get tokens => _tokens;
  bool get isLoading => _isLoading;
  ConnectionStatus get connectionStatus => _connectionStatus;
  String get errorMessage => _errorMessage;
  GoogleSignInAccount? get googleAccount => _googleAccount;
  User? get firebaseUser => _firebaseUser;
  bool get isGoogleSignedIn => _firebaseUser != null;

  Future<void> _init() async {
    _tokens = await _repository.loadTokens();

    // Check if user is already logged in on boot to prevent triggering Google chooser
    _firebaseUser = FirebaseAuth.instance.currentUser;

    // Listen to Firebase Auth state changes
    FirebaseAuth.instance.authStateChanges().listen((user) {
      _firebaseUser = user;
      notifyListeners();
    });

    // If client ID is already saved and no active user session exists, silently restore
    if (_tokens.hasClientId && _firebaseUser == null) {
      try {
        await GoogleSignIn.instance.initialize(
          clientId: kIsWeb ? _tokens.serverClientId : null,
          serverClientId: _tokens.serverClientId,
        );
        final account = await GoogleSignIn.instance.attemptLightweightAuthentication();
        if (account != null) {
          await _handleGoogleSignInSuccess(account);
        }
      } catch (_) {
        // Ignore initialization errors on boot
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _handleGoogleSignInSuccess(GoogleSignInAccount account) async {
    _googleAccount = account;
    final scopes = ['https://www.googleapis.com/auth/drive.readonly'];
    
    var auth = await account.authorizationClient.authorizationForScopes(scopes);
    auth ??= await account.authorizationClient.authorizeScopes(scopes);
    final accessToken = auth.accessToken;
    
    if (accessToken.isNotEmpty) {
      _tokens = _tokens.copyWith(accessToken: accessToken);
      await _repository.saveTokens(_tokens);
      
      final googleAuth = account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: accessToken,
        idToken: googleAuth.idToken,
      );
      
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      _firebaseUser = userCredential.user;
      _connectionStatus = ConnectionStatus.connected;
    } else {
      throw Exception('Failed to obtain Google Drive access token.');
    }
  }

  Future<bool> refreshAccessToken() async {
    if (!_tokens.hasClientId) return false;
    
    try {
      await GoogleSignIn.instance.initialize(
        clientId: kIsWeb ? _tokens.serverClientId : null,
        serverClientId: _tokens.serverClientId,
      );
      final account = await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (account != null) {
        await _handleGoogleSignInSuccess(account);
        notifyListeners();
        return true;
      }
    } catch (_) {
      // Ignore silent refresh errors
    }
    return false;
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
    _firebaseUser = null;
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
      await GoogleSignIn.instance.initialize(
        clientId: kIsWeb ? _tokens.serverClientId : null,
        serverClientId: _tokens.serverClientId,
      );

      final GoogleSignInAccount account = await GoogleSignIn.instance.authenticate();
      await _handleGoogleSignInSuccess(account);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _connectionStatus = ConnectionStatus.failed;
      final errorStr = e.toString();
      if (errorStr.contains('ApiException: 10') || errorStr.contains('sign_in_failed') || errorStr.contains('10:')) {
        _errorMessage = 'Sign in failed (Error 10): This usually means your app\'s package name or SHA-1 fingerprint is not registered in the Firebase/Google Developer Console, or the Client ID is incorrect.';
      } else {
        _errorMessage = 'Sign in failed: $errorStr';
      }
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
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    _googleAccount = null;
    _firebaseUser = null;
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
