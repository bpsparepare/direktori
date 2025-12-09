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
    String? orderBy,
    bool ascending = false,
    bool includeCoordinates = false,
  }) async {
    final mapModels = await remoteDataSource.getDirektoriList(
      page: page,
      limit: limit,
      search: search,
      orderBy: orderBy,
      ascending: ascending,
      includeCoordinates: includeCoordinates,
    );

    return mapModels
        .map((mapModel) => DirektoriModel.fromMapModel(mapModel))
        .toList();
  }

  @override
  Future<int> getDirektoriCount({String? search}) async {
    return await remoteDataSource.getDirektoriCount(search: search);
  }

  @override
  Future<Map<String, int>> getDirektoriStats({DateTime? updatedThreshold}) async {
    return await remoteDataSource.getDirektoriStats(updatedThreshold: updatedThreshold);
  }
}
