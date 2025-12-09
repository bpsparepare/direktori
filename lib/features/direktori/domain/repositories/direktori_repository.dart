import '../entities/direktori.dart';

abstract class DirektoriRepository {
  Future<List<Direktori>> getDirektoriList({
    required int page,
    required int limit,
    String? search,
    String? orderBy,
    bool ascending = false,
    bool includeCoordinates = false,
  });

  Future<int> getDirektoriCount({String? search});
  Future<Map<String, int>> getDirektoriStats({DateTime? updatedThreshold});
}
