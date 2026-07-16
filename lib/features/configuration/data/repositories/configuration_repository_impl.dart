import '../datasources/secure_storage_service.dart';
import '../../domain/entities/token_entity.dart';
import '../../domain/repositories/configuration_repository.dart';

class ConfigurationRepositoryImpl implements ConfigurationRepository {
  final SecureStorageService _secureStorage;

  ConfigurationRepositoryImpl(this._secureStorage);

  static const String _keyApiKey = 'gdrive_api_key';
  static const String _keyAccessToken = 'gdrive_access_token';
  static const String _keyServerClientId = 'gdrive_server_client_id';

  @override
  Future<TokenEntity> loadTokens() async {
    var apiKey = await _secureStorage.read(_keyApiKey) ?? '';
    final accessToken = await _secureStorage.read(_keyAccessToken) ?? '';
    var serverClientId = await _secureStorage.read(_keyServerClientId) ?? '';
    
    // Fallbacks to default values if not configured in secure storage
    if (apiKey.trim().isEmpty) {
      apiKey = const TokenEntity.empty().apiKey;
    }
    if (serverClientId.trim().isEmpty) {
      serverClientId = const TokenEntity.empty().serverClientId;
    }
    
    return TokenEntity(
      apiKey: apiKey,
      accessToken: accessToken,
      serverClientId: serverClientId,
    );
  }

  @override
  Future<void> saveTokens(TokenEntity token) async {
    await _secureStorage.write(_keyApiKey, token.apiKey.trim());
    await _secureStorage.write(_keyAccessToken, token.accessToken.trim());
    await _secureStorage.write(_keyServerClientId, token.serverClientId.trim());
  }

  @override
  Future<void> clearTokens() async {
    await _secureStorage.delete(_keyApiKey);
    await _secureStorage.delete(_keyAccessToken);
    await _secureStorage.delete(_keyServerClientId);
  }
}
