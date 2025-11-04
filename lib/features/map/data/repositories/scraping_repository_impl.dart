import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:gsheets/gsheets.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/entities/place.dart';
import '../models/scraped_place.dart';

class ScrapingRepositoryImpl {
  static const String _spreadsheetId =
      '1W82OicbyAmyzSnkp_gUsZFhOnUm4qbcc4y2ANLRP5JI';
  static const String _worksheetTitle = 'data';
  static const String _saAssetPath = 'assets/sa/sa-account.json';

  static List<ScrapedPlace>? _cached;
  static Map<String, ScrapedPlace>? _byId;

  Future<GSheets> _initClient() async {
    final jsonStr = await rootBundle.loadString(_saAssetPath);
    final gsheets = GSheets(jsonStr);
    return gsheets;
  }

  Future<List<ScrapedPlace>> getScrapedPlaces() async {
    try {
      if (_cached != null) return _cached!;
      final gsheets = await _initClient();
      final ss = await gsheets.spreadsheet(_spreadsheetId);
      final ws = ss.worksheetByTitle(_worksheetTitle);
      if (ws == null) {
        debugPrint(
          'ScrapingRepository: worksheet "$_worksheetTitle" not found',
        );
        return [];
      }
      final rows =
          await ws.values.map.allRows(fromRow: 1) ??
          const <Map<String, String>>[];
      if (rows.isEmpty) {
        debugPrint('ScrapingRepository: no rows');
        return [];
      }
      final List<ScrapedPlace> places = [];
      for (final row in rows) {
        try {
          final sp = ScrapedPlace.fromRow(row);
          // Skip without coordinates or title
          if (sp.title.isEmpty) continue;
          if (sp.latitude == 0.0 && sp.longitude == 0.0) continue;
          places.add(sp);
        } catch (e) {
          debugPrint('ScrapingRepository: parse row error: $e');
        }
      }
      _cached = places;
      _byId = {
        for (final sp in places)
          'scrape:${sp.cid?.isNotEmpty == true ? sp.cid! : '${sp.latitude},${sp.longitude},${sp.title}'}':
              sp,
      };
      debugPrint('ScrapingRepository: loaded ${places.length} scraped places');
      return places;
    } catch (e) {
      debugPrint('ScrapingRepository: error loading sheet: $e');
      return [];
    }
  }

  Future<List<Place>> getScrapedPlacesAsPlace() async {
    final sps = await getScrapedPlaces();
    return sps.map((e) => e.toPlace()).toList();
  }

  Future<ScrapedPlace?> getByPlaceId(String placeId) async {
    // Ensure cache populated
    if (_byId == null) await getScrapedPlaces();
    return _byId?[placeId];
  }

  /// Update status column in Google Sheets for a scraped place.
  /// Tries to match by `cid` first; falls back to `link` if needed.
  Future<bool> updateStatusFor(ScrapedPlace place, String status) async {
    try {
      final gsheets = await _initClient();
      final ss = await gsheets.spreadsheet(_spreadsheetId);
      final ws = ss.worksheetByTitle(_worksheetTitle);
      if (ws == null) {
        debugPrint(
            'ScrapingRepository: worksheet "$_worksheetTitle" not found');
        return false;
      }

      // Read all rows to locate the matching record and status column
      final rows = await ws.values.allRows(fromRow: 1) ?? const <List<String>>[];
      if (rows.isEmpty) {
        debugPrint('ScrapingRepository: empty sheet');
        return false;
      }

      // Determine header indices
      final headers = rows.first.map((e) => e.trim().toLowerCase()).toList();
      final int statusColIdx = headers.indexOf('status');
      final int cidColIdx = headers.indexOf('cid');
      final int linkColIdx = headers.indexOf('link');
      if (statusColIdx < 0) {
        debugPrint('ScrapingRepository: no "status" column found');
        return false;
      }

      // Scan for matching row by cid or link
      int? matchRowIdx; // zero-based index within `rows`
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        bool match = false;
        if (cidColIdx >= 0 && (place.cid?.isNotEmpty ?? false)) {
          final String cell = cidColIdx < row.length ? row[cidColIdx] : '';
          if (cell.trim() == place.cid!.trim()) match = true;
        }
        if (!match && linkColIdx >= 0) {
          final String cell = linkColIdx < row.length ? row[linkColIdx] : '';
          if (cell.trim() == place.link.trim()) match = true;
        }
        if (match) {
          matchRowIdx = i;
          break;
        }
      }

      if (matchRowIdx == null) {
        debugPrint('ScrapingRepository: no matching row for cid/link');
        return false;
      }

      // Convert to 1-based indices for insertValue
      final int rowOneBased = matchRowIdx + 1;
      final int colOneBased = statusColIdx + 1;

      final ok = await ws.values.insertValue(
        status,
        row: rowOneBased,
        column: colOneBased,
      );
      if (!ok) {
        debugPrint('ScrapingRepository: failed to update status cell');
      } else {
        // Invalidate cache to reflect updated status next fetch
        _cached = null;
        _byId = null;
      }
      return ok;
    } catch (e) {
      debugPrint('ScrapingRepository: error updateStatusFor: $e');
      return false;
    }
  }

  /// Convenience: update status by placeId (e.g., 'scrape:<cid/...>')
  Future<bool> updateStatusByPlaceId(String placeId, String status) async {
    try {
      final place = await getByPlaceId(placeId);
      if (place == null) {
        debugPrint('ScrapingRepository: placeId not found in cache');
        return false;
      }
      return updateStatusFor(place, status);
    } catch (e) {
      debugPrint('ScrapingRepository: error updateStatusByPlaceId: $e');
      return false;
    }
  }
}