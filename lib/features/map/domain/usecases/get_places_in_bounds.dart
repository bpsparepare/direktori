import '../entities/place.dart';
import '../repositories/map_repository.dart';

class GetPlacesInBounds {
  final MapRepository repository;
  GetPlacesInBounds(this.repository);

  Future<List<Place>> call(
    double south,
    double north,
    double west,
    double east,
  ) {
    return repository.getPlacesInBounds(south, north, west, east);
  }
}
