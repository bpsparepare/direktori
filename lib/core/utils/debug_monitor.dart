import 'dart:convert';
import 'package:flutter/foundation.dart';

class DebugMonitor {
  static final DebugMonitor _instance = DebugMonitor._internal();
  factory DebugMonitor() => _instance;
  DebugMonitor._internal();

  final ValueNotifier<DebugStats> statsNotifier = ValueNotifier(DebugStats());

  void logUsage(
    String table,
    String operation,
    dynamic data, {
    bool isResponse = true,
  }) {
    int size = 0;
    try {
      if (data != null) {
        size = utf8.encode(jsonEncode(data)).length;
      }
    } catch (_) {
      // Ignore encoding errors
    }

    final kb = size / 1024.0;

    // Update stats
    final current = statsNotifier.value;
    statsNotifier.value = current.copyWith(
      totalDownloadKb: isResponse
          ? current.totalDownloadKb + kb
          : current.totalDownloadKb,
      totalUploadKb: !isResponse
          ? current.totalUploadKb + kb
          : current.totalUploadKb,
      lastRequest: '$operation on $table (${isResponse ? "IN" : "OUT"})',
      lastRequestSizeKb: kb,
      requestCount: current.requestCount + 1,
    );

    // Print to console (formatted)
    final mb = kb / 1024.0;
    String sizeStr;
    if (mb >= 1.0) {
      sizeStr = '${mb.toStringAsFixed(2)} MB';
    } else {
      sizeStr = '${kb.toStringAsFixed(2)} KB';
    }

    final direction = isResponse ? 'IN (Download)' : 'OUT (Upload)';
    // debugPrint(
    //   '[CEK] $operation on $table | $direction: $sizeStr',
    // );
  }
}

class DebugStats {
  final double totalDownloadKb;
  final double totalUploadKb;
  final String lastRequest;
  final double lastRequestSizeKb;
  final int requestCount;

  DebugStats({
    this.totalDownloadKb = 0,
    this.totalUploadKb = 0,
    this.lastRequest = '-',
    this.lastRequestSizeKb = 0,
    this.requestCount = 0,
  });

  DebugStats copyWith({
    double? totalDownloadKb,
    double? totalUploadKb,
    String? lastRequest,
    double? lastRequestSizeKb,
    int? requestCount,
  }) {
    return DebugStats(
      totalDownloadKb: totalDownloadKb ?? this.totalDownloadKb,
      totalUploadKb: totalUploadKb ?? this.totalUploadKb,
      lastRequest: lastRequest ?? this.lastRequest,
      lastRequestSizeKb: lastRequestSizeKb ?? this.lastRequestSizeKb,
      requestCount: requestCount ?? this.requestCount,
    );
  }
}
