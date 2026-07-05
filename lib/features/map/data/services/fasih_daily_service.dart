import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';

class DailyContributionSummary {
  final int totalToday;
  final int totalYesterday;
  final int totalDelta;
  final int activeUnits;

  const DailyContributionSummary({
    required this.totalToday,
    required this.totalYesterday,
    required this.totalDelta,
    required this.activeUnits,
  });

  factory DailyContributionSummary.fromJson(Map<String, dynamic>? json) {
    return DailyContributionSummary(
      totalToday: _toInt(json?['total_today']),
      totalYesterday: _toInt(json?['total_yesterday']),
      totalDelta: _toInt(json?['total_delta']),
      activeUnits: _toInt(json?['active_units']),
    );
  }
}

class DailyContributionRow {
  final String unitId;
  final String title;
  final String subtitle;
  final int todayCount;
  final int yesterdayCount;
  final int delta;
  final Map<String, int> statusCountsToday;

  const DailyContributionRow({
    required this.unitId,
    required this.title,
    required this.subtitle,
    required this.todayCount,
    required this.yesterdayCount,
    required this.delta,
    required this.statusCountsToday,
  });

  factory DailyContributionRow.fromJson(Map<String, dynamic> json) {
    return DailyContributionRow(
      unitId: (json['unit_id'] ?? '').toString(),
      title: (json['title'] ?? '-').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      todayCount: _toInt(json['today_count']),
      yesterdayCount: _toInt(json['yesterday_count']),
      delta: _toInt(json['delta']),
      statusCountsToday: _intMapFromDynamic(json['status_counts_today']),
    );
  }
}

class DailyContributionPayload {
  final String targetDate;
  final String yesterday;
  final String role;
  final String level;
  final DailyContributionSummary summary;
  final List<DailyContributionRow> rows;

  const DailyContributionPayload({
    required this.targetDate,
    required this.yesterday,
    required this.role,
    required this.level,
    required this.summary,
    required this.rows,
  });

  factory DailyContributionPayload.fromJson(Map<String, dynamic> json) {
    final meta = _mapFromDynamic(json['meta']);
    return DailyContributionPayload(
      targetDate: (json['target_date'] ?? '').toString(),
      yesterday: (json['yesterday'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      level: (meta?['level'] ?? '').toString(),
      summary: DailyContributionSummary.fromJson(
        _mapFromDynamic(json['summary']),
      ),
      rows: _listFromDynamic(
        json['rows'],
      ).map((item) => DailyContributionRow.fromJson(item)).toList(),
    );
  }

  factory DailyContributionPayload.empty() {
    return DailyContributionPayload(
      targetDate: '',
      yesterday: '',
      role: '',
      level: '',
      summary: const DailyContributionSummary(
        totalToday: 0,
        totalYesterday: 0,
        totalDelta: 0,
        activeUnits: 0,
      ),
      rows: const [],
    );
  }
}

class FasihDailyService {
  final SupabaseClient _client = SupabaseConfig.client;

  Future<DailyContributionPayload> fetchDailyContribution({
    DateTime? targetDate,
    String? surveyPeriodId,
    String? pengawasId,
    String? petugasId,
    bool allPetugas = false,
    String progressMode = 'petugas',
  }) async {
    final date = targetDate ?? DateTime.now();
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    final response = await _client.rpc(
      'get_fasih_daily_contribution',
      params: {
        'p_target_date': dateStr,
        'p_survey_period_id': surveyPeriodId,
        'p_pengawas_id': pengawasId,
        'p_petugas_id': petugasId,
        'p_all_petugas': allPetugas,
        'p_progress_mode': progressMode,
      },
    );

    if (response is Map<String, dynamic>) {
      return DailyContributionPayload.fromJson(response);
    }
    if (response is Map) {
      return DailyContributionPayload.fromJson(
        response.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return DailyContributionPayload.empty();
  }
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

Map<String, dynamic>? _mapFromDynamic(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  return null;
}

List<Map<String, dynamic>> _listFromDynamic(dynamic value) {
  if (value is! List) return const [];
  return value.map((item) {
    if (item is Map<String, dynamic>) return item;
    if (item is Map) return item.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }).toList();
}

Map<String, int> _intMapFromDynamic(dynamic value) {
  final json = _mapFromDynamic(value);
  if (json == null) return const {};
  return json.map((key, val) => MapEntry(key, _toInt(val)));
}
