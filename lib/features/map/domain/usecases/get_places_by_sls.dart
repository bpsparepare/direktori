import '../entities/place.dart';
import '../repositories/map_repository.dart';

class GetPlacesBySls {
  final MapRepository repository;
  GetPlacesBySls(this.repository);

  Future<List<Place>> call(String idsls) {
    return repository.getPlacesBySls(idsls);
  }
}
