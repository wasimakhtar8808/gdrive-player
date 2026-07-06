import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/token_entity.dart';
import '../../domain/repositories/configuration_repository.dart';

class ConfigurationRepositoryImpl implements ConfigurationRepository {
  final SharedPreferences _sharedPrefs;

  ConfigurationRepositoryImpl(this._sharedPrefs);

  static const String _keyApiKey = 'gdrive_api_key';
  static const String _keyAccessToken = 'gdrive_access_token';

  @override
  Future<TokenEntity> loadTokens() async {
    final apiKey = _sharedPrefs.getString(_keyApiKey) ?? '';
    final accessToken = _sharedPrefs.getString(_keyAccessToken) ?? '';
    return TokenEntity(apiKey: apiKey, accessToken: accessToken);
  }

  @override
  Future<void> saveTokens(TokenEntity token) async {
    await _sharedPrefs.setString(_keyApiKey, token.apiKey.trim());
    await _sharedPrefs.setString(_keyAccessToken, token.accessToken.trim());
  }

  @override
  Future<void> clearTokens() async {
    await _sharedPrefs.remove(_keyApiKey);
    await _sharedPrefs.remove(_keyAccessToken);
  }
}
