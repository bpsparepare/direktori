import '../entities/place.dart';
import '../repositories/map_repository.dart';

class RefreshPlaces {
  final MapRepository repository;
  RefreshPlaces(this.repository);

  Future<List<Place>> call() {
    return repository.refreshPlaces();
  }
}
