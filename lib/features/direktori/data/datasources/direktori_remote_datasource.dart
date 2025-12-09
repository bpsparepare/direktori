import '../../../map/data/models/direktori_model.dart' as MapDirektori;
import '../../../map/domain/repositories/map_repository.dart';

abstract class DirektoriRemoteDataSource {
  Future<List<MapDirektori.DirektoriModel>> getDirektoriList({
    required int page,
    required int limit,
    String? search,
    String? orderBy,
    bool ascending = false,
    bool includeCoordinates = false,
  });

  Future<int> getDirektoriCount({String? search, bool includeCoordinates = false});
  Future<Map<String, int>> getDirektoriStats({DateTime? updatedThreshold});
}

class DirektoriRemoteDataSourceImpl implements DirektoriRemoteDataSource {
  final MapRepository mapRepository;

  DirektoriRemoteDataSourceImpl({required this.mapRepository});

  @override
  Future<List<MapDirektori.DirektoriModel>> getDirektoriList({
    required int page,
    required int limit,
    String? search,
    String? orderBy,
    bool ascending = false,
    bool includeCoordinates = false,
  }) async {
    if (search != null && search.isNotEmpty) {
      if (includeCoordinates) {
        return await mapRepository.searchAllDirectoriesPaged(
          query: search,
          page: page,
          limit: limit,
          orderBy: orderBy,
          ascending: ascending,
        );
      }
      return await mapRepository.searchDirectoriesWithoutCoordinatesPaged(
        query: search,
        page: page,
        limit: limit,
        orderBy: orderBy,
        ascending: ascending,
      );
    }

    if (includeCoordinates) {
      return await mapRepository.listAllDirectories(
        page: page,
        limit: limit,
        orderBy: orderBy,
        ascending: ascending,
      );
    }
    return await mapRepository.listDirectoriesWithoutCoordinates(
      page: page,
      limit: limit,
      orderBy: orderBy,
      ascending: ascending,
    );
  }

  @override
  Future<int> getDirektoriCount({String? search, bool includeCoordinates = false}) async {
    if (includeCoordinates) {
      return await mapRepository.countAllDirectories(search: search);
    }
    if (search != null && search.isNotEmpty) {
      final results = await mapRepository.searchDirectoriesWithoutCoordinates(
        search,
      );
      return results.length;
    }
    return await mapRepository.countDirectoriesWithoutCoordinates();
  }

  @override
  Future<Map<String, int>> getDirektoriStats({DateTime? updatedThreshold}) async {
    return await mapRepository.getDirektoriStats(updatedThreshold: updatedThreshold);
  }
}
