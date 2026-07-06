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

  TokenEntity get tokens => _tokens;
  bool get isLoading => _isLoading;
  ConnectionStatus get connectionStatus => _connectionStatus;
  String get errorMessage => _errorMessage;
  GoogleSignInAccount? get googleAccount => _googleAccount;
  bool get isGoogleSignedIn => _googleAccount != null;

  Future<void> _init() async {
    _tokens = await _repository.loadTokens();

    // Initialize GoogleSignIn and register authentication state listener
    try {
      await GoogleSignIn.instance.initialize();
      
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

      // Silently request lightweight authentication to recover session
      await GoogleSignIn.instance.attemptLightweightAuthentication();
    } catch (_) {
      // Ignore initialization errors on boot
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> saveConfig(String apiKey, String accessToken) async {
    _isLoading = true;
    _connectionStatus = ConnectionStatus.idle;
    _errorMessage = '';
    notifyListeners();

    _tokens = TokenEntity(apiKey: apiKey, accessToken: accessToken);
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
    _isLoading = true;
    _connectionStatus = ConnectionStatus.testing;
    _errorMessage = '';
    notifyListeners();

    try {
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
      _errorMessage = 'Both API Key and Access Token are empty.';
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
