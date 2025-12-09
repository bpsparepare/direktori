import '../repositories/direktori_repository.dart';

class GetDirektoriStats {
  final DirektoriRepository repository;
  const GetDirektoriStats(this.repository);

  Future<Map<String, int>> call({DateTime? updatedThreshold}) {
    return repository.getDirektoriStats(updatedThreshold: updatedThreshold);
  }
}

