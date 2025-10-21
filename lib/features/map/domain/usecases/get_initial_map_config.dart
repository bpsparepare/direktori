import '../entities/map_config.dart';
import '../repositories/map_repository.dart';

class GetInitialMapConfig {
  final MapRepository repository;
  GetInitialMapConfig(this.repository);

  Future<MapConfig> call() {
    return repository.getInitialConfig();
  }
}