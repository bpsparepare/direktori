import '../entities/place.dart';
import '../repositories/map_repository.dart';

class GetPlaces {
  final MapRepository repository;
  GetPlaces(this.repository);

  Future<List<Place>> call() {
    return repository.getPlaces();
  }
}