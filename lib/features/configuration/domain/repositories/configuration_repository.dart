import '../entities/token_entity.dart';

abstract class ConfigurationRepository {
  Future<TokenEntity> loadTokens();
  Future<void> saveTokens(TokenEntity token);
  Future<void> clearTokens();
}
