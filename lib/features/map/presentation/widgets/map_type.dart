enum MapType {
  street,
  satellite,
  bingSatellite,
  googleSatellite,
  topographic,
  light,
}

extension MapTypeExtension on MapType {
  String get name {
    switch (this) {
      case MapType.street:
        return 'Street';
      case MapType.satellite:
        return 'Satelit (Esri)';
      case MapType.bingSatellite:
        return 'Satelit (Alternatif)';
      case MapType.googleSatellite:
        return 'Satelit (Google)';
      case MapType.topographic:
        return 'Topografi';
      case MapType.light:
        return 'Light';
    }
  }

  String get urlTemplate {
    switch (this) {
      case MapType.street:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapType.satellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case MapType.bingSatellite:
        return 'https://khm{s}.google.com/kh/v=101&x={x}&y={y}&z={z}';
      case MapType.googleSatellite:
        return 'https://mt{s}.google.com/vt/lyrs=s&x={x}&y={y}&z={z}';
      case MapType.topographic:
        return 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png';
      case MapType.light:
        return 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
    }
  }

  List<String> get subdomains {
    switch (this) {
      case MapType.street:
        return ['a', 'b', 'c'];
      case MapType.satellite:
        return [];
      case MapType.bingSatellite:
        return ['0', '1', '2', '3'];
      case MapType.googleSatellite:
        return ['0', '1', '2', '3'];
      case MapType.topographic:
        return ['a', 'b', 'c'];
      case MapType.light:
        return ['a', 'b', 'c', 'd'];
    }
  }

  int get maxZoom {
    switch (this) {
      case MapType.street:
        return 19;
      case MapType.satellite:
        return 18;
      case MapType.bingSatellite:
        return 19;
      case MapType.googleSatellite:
        return 20;
      case MapType.topographic:
        return 17;
      case MapType.light:
        return 19;
    }
  }
}
