import '../entities/direktori.dart';

abstract class DirektoriRepository {
  Future<List<Direktori>> getDirektoriList({
    required int page,
    required int limit,
    String? search,
  });

  Future<int> getDirektoriCount({String? search});
}
