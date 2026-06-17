import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';

class FasihRekapSummary {
  final String level;
  final int totalUnits;
  final int totalAssignments;

  const FasihRekapSummary({
    required this.level,
    required this.totalUnits,
    required this.totalAssignments,
  });

  factory FasihRekapSummary.fromJson(Map<String, dynamic>? json) {
    return FasihRekapSummary(
      level: (json?['level'] ?? '').toString(),
      totalUnits: _toInt(json?['total_units']),
      totalAssignments: _toInt(json?['total_assignments']),
    );
  }
}

class FasihRekapStatusAlias {
  final String alias;
  final int total;

  const FasihRekapStatusAlias({required this.alias, required this.total});

  factory FasihRekapStatusAlias.fromJson(Map<String, dynamic> json) {
    return FasihRekapStatusAlias(
      alias: (json['status_alias'] ?? '').toString(),
      total: _toInt(json['total']),
    );
  }
}

class FasihRekapChartItem {
  final String unitId;
  final String label;
  final int totalAssignment;

  const FasihRekapChartItem({
    required this.unitId,
    required this.label,
    required this.totalAssignment,
  });

  factory FasihRekapChartItem.fromJson(Map<String, dynamic> json) {
    return FasihRekapChartItem(
      unitId: (json['unit_id'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      totalAssignment: _toInt(json['total_assignment']),
    );
  }
}

class FasihRekapRow {
  final String unitId;
  final String title;
  final String subtitle;
  final int totalAssignment;
  final Map<String, int> statusCounts;

  const FasihRekapRow({
    required this.unitId,
    required this.title,
    required this.subtitle,
    required this.totalAssignment,
    required this.statusCounts,
  });

  factory FasihRekapRow.fromJson(Map<String, dynamic> json) {
    return FasihRekapRow(
      unitId: (json['unit_id'] ?? '').toString(),
      title: (json['title'] ?? '-').toString(),
      subtitle: (json['subtitle'] ?? '-').toString(),
      totalAssignment: _toInt(json['total_assignment']),
      statusCounts: _intMapFromDynamic(json['status_counts']),
    );
  }
}

class FasihSurveyPeriodOption {
  final String surveyPeriodId;
  final String name;
  final bool isActive;
  final String startDate;
  final String endDate;

  const FasihSurveyPeriodOption({
    required this.surveyPeriodId,
    required this.name,
    required this.isActive,
    required this.startDate,
    required this.endDate,
  });

  factory FasihSurveyPeriodOption.fromJson(Map<String, dynamic> json) {
    return FasihSurveyPeriodOption(
      surveyPeriodId: (json['survey_period_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      isActive: json['is_active'] == true,
      startDate: (json['start_date'] ?? '').toString(),
      endDate: (json['end_date'] ?? '').toString(),
    );
  }
}

class FasihRekapMeta {
  final String level;
  final int limit;
  final int offset;
  final int returnedRows;
  final String sortBy;
  final String sortDir;

  const FasihRekapMeta({
    required this.level,
    required this.limit,
    required this.offset,
    required this.returnedRows,
    required this.sortBy,
    required this.sortDir,
  });

  factory FasihRekapMeta.fromJson(Map<String, dynamic>? json) {
    return FasihRekapMeta(
      level: (json?['level'] ?? '').toString(),
      limit: _toInt(json?['limit']),
      offset: _toInt(json?['offset']),
      returnedRows: _toInt(json?['returned_rows']),
      sortBy: (json?['sort_by'] ?? '').toString(),
      sortDir: (json?['sort_dir'] ?? '').toString(),
    );
  }
}

class FasihRekapPayload {
  final FasihRekapSummary summary;
  final List<FasihRekapChartItem> chart;
  final List<FasihRekapRow> rows;
  final List<FasihRekapStatusAlias> statusAliases;
  final List<FasihSurveyPeriodOption> periods;
  final FasihRekapMeta meta;

  const FasihRekapPayload({
    required this.summary,
    required this.chart,
    required this.rows,
    required this.statusAliases,
    required this.periods,
    required this.meta,
  });

  factory FasihRekapPayload.fromJson(Map<String, dynamic> json) {
    return FasihRekapPayload(
      summary: FasihRekapSummary.fromJson(_mapFromDynamic(json['summary'])),
      chart: _listFromDynamic(
        json['chart'],
      ).map((item) => FasihRekapChartItem.fromJson(item)).toList(),
      rows: _listFromDynamic(
        json['rows'],
      ).map((item) => FasihRekapRow.fromJson(item)).toList(),
      statusAliases: _listFromDynamic(
        json['status_aliases'],
      ).map((item) => FasihRekapStatusAlias.fromJson(item)).toList(),
      periods: _listFromDynamic(
        json['periods'],
      ).map((item) => FasihSurveyPeriodOption.fromJson(item)).toList(),
      meta: FasihRekapMeta.fromJson(_mapFromDynamic(json['meta'])),
    );
  }

  factory FasihRekapPayload.empty() {
    return FasihRekapPayload(
      summary: const FasihRekapSummary(
        level: '',
        totalUnits: 0,
        totalAssignments: 0,
      ),
      chart: const [],
      rows: const [],
      statusAliases: const [],
      periods: const [],
      meta: const FasihRekapMeta(
        level: '',
        limit: 20,
        offset: 0,
        returnedRows: 0,
        sortBy: 'total_assignment',
        sortDir: 'desc',
      ),
    );
  }
}

class FasihRekapService {
  final SupabaseClient _client = SupabaseConfig.client;

  Future<FasihRekapPayload> fetchPendataWilayah({
    String? surveyPeriodId,
    String? search,
    int limit = 200,
    int offset = 0,
    String sortBy = 'title',
    String sortDir = 'asc',
  }) => _callRpc('get_fasih_rekap_pendata_wilayah', {
    'p_survey_period_id': surveyPeriodId,
    'p_search': _normalizeSearch(search),
    'p_limit': limit,
    'p_offset': offset,
    'p_sort_by': sortBy,
    'p_sort_dir': sortDir,
  });

  Future<FasihRekapPayload> fetchPengawasPetugas({
    String? surveyPeriodId,
    String? search,
    int limit = 100,
    int offset = 0,
    String sortBy = 'total_assignment',
    String sortDir = 'desc',
  }) => _callRpc('get_fasih_rekap_pengawas_petugas', {
    'p_survey_period_id': surveyPeriodId,
    'p_search': _normalizeSearch(search),
    'p_limit': limit,
    'p_offset': offset,
    'p_sort_by': sortBy,
    'p_sort_dir': sortDir,
  });

  Future<FasihRekapPayload> fetchPengawasWilayahPetugas({
    required String petugasId,
    String? surveyPeriodId,
    String? search,
    int limit = 200,
    int offset = 0,
    String sortBy = 'title',
    String sortDir = 'asc',
  }) => _callRpc('get_fasih_rekap_pengawas_wilayah_petugas', {
    'p_petugas_id': petugasId,
    'p_survey_period_id': surveyPeriodId,
    'p_search': _normalizeSearch(search),
    'p_limit': limit,
    'p_offset': offset,
    'p_sort_by': sortBy,
    'p_sort_dir': sortDir,
  });

  Future<FasihRekapPayload> fetchAdminPengawas({
    String? surveyPeriodId,
    String? search,
    int limit = 100,
    int offset = 0,
    String sortBy = 'total_assignment',
    String sortDir = 'desc',
  }) => _callRpc('get_fasih_rekap_admin_pengawas', {
    'p_survey_period_id': surveyPeriodId,
    'p_search': _normalizeSearch(search),
    'p_limit': limit,
    'p_offset': offset,
    'p_sort_by': sortBy,
    'p_sort_dir': sortDir,
  });

  Future<FasihRekapPayload> fetchAdminPetugasByPengawas({
    required String pengawasId,
    String? surveyPeriodId,
    String? search,
    int limit = 150,
    int offset = 0,
    String sortBy = 'total_assignment',
    String sortDir = 'desc',
  }) => _callRpc('get_fasih_rekap_admin_petugas_by_pengawas', {
    'p_pengawas_id': pengawasId,
    'p_survey_period_id': surveyPeriodId,
    'p_search': _normalizeSearch(search),
    'p_limit': limit,
    'p_offset': offset,
    'p_sort_by': sortBy,
    'p_sort_dir': sortDir,
  });

  Future<FasihRekapPayload> fetchAdminPetugas({
    String? surveyPeriodId,
    String? search,
    int limit = 150,
    int offset = 0,
    String sortBy = 'total_assignment',
    String sortDir = 'desc',
  }) => _callRpc('get_fasih_rekap_admin_petugas', {
    'p_survey_period_id': surveyPeriodId,
    'p_search': _normalizeSearch(search),
    'p_limit': limit,
    'p_offset': offset,
    'p_sort_by': sortBy,
    'p_sort_dir': sortDir,
  });

  Future<FasihRekapPayload> fetchAdminWilayahByPetugas({
    required String petugasId,
    String? surveyPeriodId,
    String? search,
    int limit = 250,
    int offset = 0,
    String sortBy = 'title',
    String sortDir = 'asc',
  }) => _callRpc('get_fasih_rekap_admin_wilayah_by_petugas', {
    'p_petugas_id': petugasId,
    'p_survey_period_id': surveyPeriodId,
    'p_search': _normalizeSearch(search),
    'p_limit': limit,
    'p_offset': offset,
    'p_sort_by': sortBy,
    'p_sort_dir': sortDir,
  });

  Future<FasihRekapPayload> _callRpc(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    final response = await _client.rpc(functionName, params: params);
    if (response is Map<String, dynamic>) {
      return FasihRekapPayload.fromJson(response);
    }
    if (response is Map) {
      return FasihRekapPayload.fromJson(
        response.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return FasihRekapPayload.empty();
  }

  String? _normalizeSearch(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

Map<String, dynamic>? _mapFromDynamic(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return null;
}

List<Map<String, dynamic>> _listFromDynamic(dynamic value) {
  if (value is! List) return const [];
  return value.map((item) {
    if (item is Map<String, dynamic>) return item;
    if (item is Map) {
      return item.map((key, val) => MapEntry(key.toString(), val));
    }
    return <String, dynamic>{};
  }).toList();
}

Map<String, int> _intMapFromDynamic(dynamic value) {
  final json = _mapFromDynamic(value);
  if (json == null) return const {};
  return json.map((key, val) => MapEntry(key, _toInt(val)));
}
