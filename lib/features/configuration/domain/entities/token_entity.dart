class TokenEntity {
  final String apiKey;
  final String accessToken;

  const TokenEntity({
    required this.apiKey,
    required this.accessToken,
  });

  bool get isEmpty => apiKey.trim().isEmpty && accessToken.trim().isEmpty;
  bool get hasApiKey => apiKey.trim().isNotEmpty;
  bool get hasAccessToken => accessToken.trim().isNotEmpty;

  TokenEntity copyWith({
    String? apiKey,
    String? accessToken,
  }) {
    return TokenEntity(
      apiKey: apiKey ?? this.apiKey,
      accessToken: accessToken ?? this.accessToken,
    );
  }

  const TokenEntity.empty()
      : apiKey = '',
        accessToken = '';
}
