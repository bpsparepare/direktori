import '../../domain/entities/direktori.dart';
import '../../domain/repositories/direktori_repository.dart';
import '../datasources/direktori_remote_datasource.dart';
import '../models/direktori_model.dart';

class DirektoriRepositoryImpl implements DirektoriRepository {
  final DirektoriRemoteDataSource remoteDataSource;

  DirektoriRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<Direktori>> getDirektoriList({
    required int page,
    required int limit,
    String? search,
  }) async {
    final mapModels = await remoteDataSource.getDirektoriList(
      page: page,
      limit: limit,
      search: search,
    );

    return mapModels
        .map((mapModel) => DirektoriModel.fromMapModel(mapModel))
        .toList();
  }

  @override
  Future<int> getDirektoriCount({String? search}) async {
    return await remoteDataSource.getDirektoriCount(search: search);
  }
}
