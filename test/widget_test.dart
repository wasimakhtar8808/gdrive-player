import 'package:flutter_test/flutter_test.dart';
import 'package:gdrive_player/features/configuration/domain/entities/token_entity.dart';

void main() {
  group('TokenEntity Tests', () {
    test('Default TokenEntity initialization values', () {
      const entity = TokenEntity.empty();
      expect(entity.apiKey, 'AIzaSyCwEDejUR4FXG3KZAvTZ10Es7qYCIHp7d8');
      expect(entity.accessToken, isEmpty);
      expect(entity.serverClientId, '728182534182-2gsap6poc95l9l7mb3al4ivbhruseo4l.apps.googleusercontent.com');
      expect(entity.hasClientId, isTrue);
    });

    test('Custom TokenEntity initialization values', () {
      const entity = TokenEntity(
        apiKey: 'test-api-key',
        accessToken: 'test-access-token',
        serverClientId: 'test-client-id',
      );
      expect(entity.apiKey, 'test-api-key');
      expect(entity.accessToken, 'test-access-token');
      expect(entity.serverClientId, 'test-client-id');
      expect(entity.hasClientId, isTrue);
    });
  });
}
