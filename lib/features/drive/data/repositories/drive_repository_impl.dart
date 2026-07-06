import '../../../configuration/domain/entities/token_entity.dart';
import '../../domain/entities/drive_item.dart';
import '../../domain/repositories/drive_repository.dart';
import '../datasources/drive_remote_data_source.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';

class DriveRepositoryImpl implements DriveRepository {
  final DriveRemoteDataSource _dataSource;

  DriveRepositoryImpl(this._dataSource);

  @override
  Future<List<DriveItem>> getDriveContents({
    required String folderId,
    required TokenEntity token,
  }) async {
    try {
      return await _dataSource.fetchFiles(folderId: folderId, token: token);
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    } on ServerException catch (e) {
      throw ServerFailure(e.message);
    } on NetworkException catch (e) {
      throw NetworkFailure(e.message);
    } catch (e) {
      throw ServerFailure(e.toString());
    }
  }

  @override
  Future<List<DriveItem>> searchDrive({
    required String query,
    required TokenEntity token,
  }) async {
    try {
      return await _dataSource.searchFiles(searchPattern: query, token: token);
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    } on ServerException catch (e) {
      throw ServerFailure(e.message);
    } on NetworkException catch (e) {
      throw NetworkFailure(e.message);
    } catch (e) {
      throw ServerFailure(e.toString());
    }
  }
}
