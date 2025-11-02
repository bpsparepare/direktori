import '../../../map/data/models/direktori_model.dart' as MapDirektori;
import '../../../map/domain/repositories/map_repository.dart';

abstract class DirektoriRemoteDataSource {
  Future<List<MapDirektori.DirektoriModel>> getDirektoriList({
    required int page,
    required int limit,
    String? search,
  });

  Future<int> getDirektoriCount({String? search});
}

class DirektoriRemoteDataSourceImpl implements DirektoriRemoteDataSource {
  final MapRepository mapRepository;

  DirektoriRemoteDataSourceImpl({required this.mapRepository});

  @override
  Future<List<MapDirektori.DirektoriModel>> getDirektoriList({
    required int page,
    required int limit,
    String? search,
  }) async {
    // For now, we'll use the existing search method
    // In a real implementation, this would be a proper paginated API call
    if (search != null && search.isNotEmpty) {
      final allResults = await mapRepository
          .searchDirectoriesWithoutCoordinates(search);
      final startIndex = (page - 1) * limit;
      final endIndex = startIndex + limit;

      if (startIndex >= allResults.length) return [];

      return allResults.sublist(
        startIndex,
        endIndex > allResults.length ? allResults.length : endIndex,
      );
    }

    // If no search, return empty for now
    // In real implementation, this would fetch all directories with pagination
    return [];
  }

  @override
  Future<int> getDirektoriCount({String? search}) async {
    // For now, we'll use the existing search method to get count
    if (search != null && search.isNotEmpty) {
      final results = await mapRepository.searchDirectoriesWithoutCoordinates(
        search,
      );
      return results.length;
    }

    // If no search, return 0 for now
    // In real implementation, this would return total count from database
    return 0;
  }
}
