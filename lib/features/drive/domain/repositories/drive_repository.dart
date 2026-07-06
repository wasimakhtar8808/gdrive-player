import '../../../configuration/domain/entities/token_entity.dart';
import '../entities/drive_item.dart';

abstract class DriveRepository {
  Future<List<DriveItem>> getDriveContents({
    required String folderId,
    required TokenEntity token,
  });

  Future<List<DriveItem>> searchDrive({
    required String query,
    required TokenEntity token,
  });
}
