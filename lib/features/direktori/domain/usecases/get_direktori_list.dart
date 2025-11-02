import '../entities/direktori.dart';
import '../repositories/direktori_repository.dart';

class GetDirektoriList {
  final DirektoriRepository repository;

  GetDirektoriList(this.repository);

  Future<List<Direktori>> call({
    required int page,
    required int limit,
    String? search,
  }) async {
    return await repository.getDirektoriList(
      page: page,
      limit: limit,
      search: search,
    );
  }
}

class GetDirektoriCount {
  final DirektoriRepository repository;

  GetDirektoriCount(this.repository);

  Future<int> call({String? search}) async {
    return await repository.getDirektoriCount(search: search);
  }
}
