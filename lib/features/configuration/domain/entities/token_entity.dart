class TokenEntity {
  final String apiKey;
  final String accessToken;
  final String serverClientId;

  const TokenEntity({
    required this.apiKey,
    required this.accessToken,
    required this.serverClientId,
  });

  bool get isEmpty => apiKey.trim().isEmpty && accessToken.trim().isEmpty && serverClientId.trim().isEmpty;
  bool get hasApiKey => apiKey.trim().isNotEmpty;
  bool get hasAccessToken => accessToken.trim().isNotEmpty;
  bool get hasClientId => serverClientId.trim().isNotEmpty;

  TokenEntity copyWith({
    String? apiKey,
    String? accessToken,
    String? serverClientId,
  }) {
    return TokenEntity(
      apiKey: apiKey ?? this.apiKey,
      accessToken: accessToken ?? this.accessToken,
      serverClientId: serverClientId ?? this.serverClientId,
    );
  }

  const TokenEntity.empty()
      : apiKey = '',
        accessToken = '',
        serverClientId = '';
}
