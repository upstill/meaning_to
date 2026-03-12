import 'dart:async';

/// Performance profiler for tracking cache operations and database writes
/// Helps identify bottlenecks when dealing with large numbers of tasks
class PerformanceProfiler {
  static final PerformanceProfiler _instance = PerformanceProfiler._internal();
  factory PerformanceProfiler() => _instance;
  PerformanceProfiler._internal();

  // Performance metrics
  final Map<String, List<Duration>> _operationDurations = {};
  final Map<String, int> _operationCounts = {};
  final Map<String, DateTime> _operationStartTimes = {};

  // Database write tracking
  final List<DatabaseWrite> _databaseWrites = [];
  final Map<String, int> _writeCountsByOperation = {};

  // Cache operation tracking
  final List<CacheOperation> _cacheOperations = [];
  final Map<String, int> _cacheOperationCounts = {};

  // Memory usage tracking
  final List<MemorySnapshot> _memorySnapshots = [];

  // Performance thresholds
  static const Duration _slowOperationThreshold = Duration(milliseconds: 100);
  static const Duration _verySlowOperationThreshold =
      Duration(milliseconds: 500);
  static const int _maxDatabaseWritesPerMinute = 60;
  static const int _maxCacheOperationsPerMinute = 100;

  /// Start timing an operation
  void startOperation(String operationName) {
    _operationStartTimes[operationName] = DateTime.now();
    _operationCounts[operationName] =
        (_operationCounts[operationName] ?? 0) + 1;
  }

  /// End timing an operation and record the duration
  void endOperation(String operationName) {
    final startTime = _operationStartTimes[operationName];
    if (startTime != null) {
      final duration = DateTime.now().difference(startTime);
      _operationDurations.putIfAbsent(operationName, () => []).add(duration);

      // Log slow operations
      if (duration > _verySlowOperationThreshold) {
        print(
            '🚨 VERY SLOW OPERATION: $operationName took ${duration.inMilliseconds}ms');
      } else if (duration > _slowOperationThreshold) {
        print(
            '⚠️ SLOW OPERATION: $operationName took ${duration.inMilliseconds}ms');
      }

      _operationStartTimes.remove(operationName);
    }
  }

  /// Record a database write operation
  void recordDatabaseWrite(
      String operation, String table, Map<String, dynamic> data,
      {String? taskId, String? categoryId}) {
    final write = DatabaseWrite(
      timestamp: DateTime.now(),
      operation: operation,
      table: table,
      dataKeys: data.keys.toList(),
      dataSize: data.toString().length,
      taskId: taskId,
      categoryId: categoryId,
    );

    _databaseWrites.add(write);
    _writeCountsByOperation[operation] =
        (_writeCountsByOperation[operation] ?? 0) + 1;

    // Check for excessive writes
    _checkWriteFrequency();
  }

  /// Record a cache operation
  void recordCacheOperation(String operation, int taskCount,
      {String? details}) {
    final cacheOp = CacheOperation(
      timestamp: DateTime.now(),
      operation: operation,
      taskCount: taskCount,
      details: details,
    );

    _cacheOperations.add(cacheOp);
    _cacheOperationCounts[operation] =
        (_cacheOperationCounts[operation] ?? 0) + 1;

    // Check for excessive cache operations
    _checkCacheOperationFrequency();
  }

  /// Take a memory snapshot
  void takeMemorySnapshot(String context, {int? taskCount, int? cacheSize}) {
    final snapshot = MemorySnapshot(
      timestamp: DateTime.now(),
      context: context,
      taskCount: taskCount,
      cacheSize: cacheSize,
    );

    _memorySnapshots.add(snapshot);
  }

  /// Check if database writes are happening too frequently
  void _checkWriteFrequency() {
    final oneMinuteAgo = DateTime.now().subtract(Duration(minutes: 1));
    final recentWrites = _databaseWrites
        .where((write) => write.timestamp.isAfter(oneMinuteAgo))
        .length;

    if (recentWrites > _maxDatabaseWritesPerMinute) {
      print(
          '🚨 HIGH DATABASE WRITE FREQUENCY: $recentWrites writes in the last minute');
      print(
          '   Consider implementing write batching or reducing update frequency');
    }
  }

  /// Check if cache operations are happening too frequently
  void _checkCacheOperationFrequency() {
    final oneMinuteAgo = DateTime.now().subtract(Duration(minutes: 1));
    final recentOperations = _cacheOperations
        .where((op) => op.timestamp.isAfter(oneMinuteAgo))
        .length;

    if (recentOperations > _maxCacheOperationsPerMinute) {
      print(
          '🚨 HIGH CACHE OPERATION FREQUENCY: $recentOperations operations in the last minute');
      print(
          '   Consider implementing operation batching or reducing cache updates');
    }
  }

  /// Get performance summary
  Map<String, dynamic> getPerformanceSummary() {
    final summary = <String, dynamic>{};

    // Operation timing statistics
    final timingStats = <String, Map<String, dynamic>>{};
    for (final entry in _operationDurations.entries) {
      final durations = entry.value;
      if (durations.isNotEmpty) {
        durations.sort();
        final avg = durations.fold(0, (sum, d) => sum + d.inMilliseconds) /
            durations.length;
        final median = durations[durations.length ~/ 2].inMilliseconds;
        final min = durations.first.inMilliseconds;
        final max = durations.last.inMilliseconds;

        timingStats[entry.key] = {
          'count': durations.length,
          'avg_ms': avg.round(),
          'median_ms': median,
          'min_ms': min,
          'max_ms': max,
          'total_ms': durations.fold(0, (sum, d) => sum + d.inMilliseconds),
        };
      }
    }
    summary['timing_stats'] = timingStats;

    // Database write statistics
    final writeStats = <String, dynamic>{
      'total_writes': _databaseWrites.length,
      'writes_by_operation': Map<String, int>.from(_writeCountsByOperation),
      'recent_writes': _databaseWrites
          .where((w) => w.timestamp
              .isAfter(DateTime.now().subtract(Duration(minutes: 5))))
          .length,
    };
    summary['database_writes'] = writeStats;

    // Cache operation statistics
    final cacheStats = <String, dynamic>{
      'total_operations': _cacheOperations.length,
      'operations_by_type': Map<String, int>.from(_cacheOperationCounts),
      'recent_operations': _cacheOperations
          .where((op) => op.timestamp
              .isAfter(DateTime.now().subtract(Duration(minutes: 5))))
          .length,
    };
    summary['cache_operations'] = cacheStats;

    // Memory snapshots
    summary['memory_snapshots'] = _memorySnapshots.length;

    return summary;
  }

  /// Get detailed performance report
  String getDetailedReport() {
    final buffer = StringBuffer();
    buffer.writeln('=== PERFORMANCE PROFILER REPORT ===');
    buffer.writeln('Generated: ${DateTime.now()}');
    buffer.writeln();

    // Timing statistics
    buffer.writeln('OPERATION TIMING:');
    final timingStats =
        getPerformanceSummary()['timing_stats'] as Map<String, dynamic>;
    for (final entry in timingStats.entries) {
      final stats = entry.value as Map<String, dynamic>;
      buffer.writeln('  ${entry.key}:');
      buffer.writeln('    Count: ${stats['count']}');
      buffer.writeln('    Avg: ${stats['avg_ms']}ms');
      buffer.writeln('    Median: ${stats['median_ms']}ms');
      buffer.writeln('    Min: ${stats['min_ms']}ms');
      buffer.writeln('    Max: ${stats['max_ms']}ms');
      buffer.writeln('    Total: ${stats['total_ms']}ms');
      buffer.writeln();
    }

    // Database writes
    buffer.writeln('DATABASE WRITES:');
    final writeStats =
        getPerformanceSummary()['database_writes'] as Map<String, dynamic>;
    buffer.writeln('  Total writes: ${writeStats['total_writes']}');
    buffer.writeln('  Recent writes (5min): ${writeStats['recent_writes']}');
    buffer.writeln('  Writes by operation:');
    final writesByOp =
        writeStats['writes_by_operation'] as Map<String, dynamic>;
    for (final entry in writesByOp.entries) {
      buffer.writeln('    ${entry.key}: ${entry.value}');
    }
    buffer.writeln();

    // Cache operations
    buffer.writeln('CACHE OPERATIONS:');
    final cacheStats =
        getPerformanceSummary()['cache_operations'] as Map<String, dynamic>;
    buffer.writeln('  Total operations: ${cacheStats['total_operations']}');
    buffer.writeln(
        '  Recent operations (5min): ${cacheStats['recent_operations']}');
    buffer.writeln('  Operations by type:');
    final opsByType = cacheStats['operations_by_type'] as Map<String, dynamic>;
    for (final entry in opsByType.entries) {
      buffer.writeln('    ${entry.key}: ${entry.value}');
    }
    buffer.writeln();

    // Performance recommendations
    buffer.writeln('PERFORMANCE RECOMMENDATIONS:');
    _generateRecommendations(buffer);

    return buffer.toString();
  }

  /// Generate performance recommendations
  void _generateRecommendations(StringBuffer buffer) {
    final summary = getPerformanceSummary();
    final timingStats = summary['timing_stats'] as Map<String, dynamic>;
    final writeStats = summary['database_writes'] as Map<String, dynamic>;
    final cacheStats = summary['cache_operations'] as Map<String, dynamic>;

    // Check for slow operations
    for (final entry in timingStats.entries) {
      final stats = entry.value as Map<String, dynamic>;
      final avgMs = stats['avg_ms'] as int;
      final count = stats['count'] as int;

      if (avgMs > 500) {
        buffer.writeln(
            '  🚨 ${entry.key} is very slow (${avgMs}ms avg) - consider optimization');
      } else if (avgMs > 100) {
        buffer.writeln(
            '  ⚠️ ${entry.key} is slow (${avgMs}ms avg) - monitor closely');
      }

      if (count > 100) {
        buffer.writeln(
            '  📊 ${entry.key} called frequently ($count times) - consider caching');
      }
    }

    // Check database write frequency
    final recentWrites = writeStats['recent_writes'] as int;
    if (recentWrites > 50) {
      buffer.writeln(
          '  🚨 High database write frequency ($recentWrites in 5min) - implement batching');
    }

    // Check cache operation frequency
    final recentOps = cacheStats['recent_operations'] as int;
    if (recentOps > 80) {
      buffer.writeln(
          '  🚨 High cache operation frequency ($recentOps in 5min) - reduce updates');
    }

    // General recommendations
    buffer.writeln('  💡 Consider implementing:');
    buffer.writeln('    - Database write batching for bulk operations');
    buffer.writeln('    - Cache update debouncing for frequent changes');
    buffer.writeln('    - Lazy loading for large task lists');
    buffer.writeln('    - Pagination for categories with 100+ tasks');
  }

  /// Clear all performance data
  void clear() {
    _operationDurations.clear();
    _operationCounts.clear();
    _operationStartTimes.clear();
    _databaseWrites.clear();
    _writeCountsByOperation.clear();
    _cacheOperations.clear();
    _cacheOperationCounts.clear();
    _memorySnapshots.clear();
  }

  /// Get recent database writes (last N minutes)
  List<DatabaseWrite> getRecentDatabaseWrites(int minutes) {
    final cutoff = DateTime.now().subtract(Duration(minutes: minutes));
    return _databaseWrites
        .where((write) => write.timestamp.isAfter(cutoff))
        .toList();
  }

  /// Get recent cache operations (last N minutes)
  List<CacheOperation> getRecentCacheOperations(int minutes) {
    final cutoff = DateTime.now().subtract(Duration(minutes: minutes));
    return _cacheOperations
        .where((op) => op.timestamp.isAfter(cutoff))
        .toList();
  }
}

/// Represents a database write operation
class DatabaseWrite {
  final DateTime timestamp;
  final String operation;
  final String table;
  final List<String> dataKeys;
  final int dataSize;
  final String? taskId;
  final String? categoryId;

  DatabaseWrite({
    required this.timestamp,
    required this.operation,
    required this.table,
    required this.dataKeys,
    required this.dataSize,
    this.taskId,
    this.categoryId,
  });

  @override
  String toString() {
    return 'DatabaseWrite($operation on $table, ${dataKeys.length} fields, ${dataSize} chars)';
  }
}

/// Represents a cache operation
class CacheOperation {
  final DateTime timestamp;
  final String operation;
  final int taskCount;
  final String? details;

  CacheOperation({
    required this.timestamp,
    required this.operation,
    required this.taskCount,
    this.details,
  });

  @override
  String toString() {
    return 'CacheOperation($operation, $taskCount tasks${details != null ? ', $details' : ''})';
  }
}

/// Represents a memory usage snapshot
class MemorySnapshot {
  final DateTime timestamp;
  final String context;
  final int? taskCount;
  final int? cacheSize;

  MemorySnapshot({
    required this.timestamp,
    required this.context,
    this.taskCount,
    this.cacheSize,
  });

  @override
  String toString() {
    return 'MemorySnapshot($context, ${taskCount ?? 'unknown'} tasks, ${cacheSize ?? 'unknown'} cache size)';
  }
}

/// Performance monitoring mixin for easy integration
mixin PerformanceMonitoring {
  final PerformanceProfiler _profiler = PerformanceProfiler();

  /// Monitor a function execution
  Future<T> monitorOperation<T>(
      String operationName, Future<T> Function() operation) async {
    _profiler.startOperation(operationName);
    try {
      final result = await operation();
      return result;
    } finally {
      _profiler.endOperation(operationName);
    }
  }

  /// Monitor a synchronous function execution
  T monitorSyncOperation<T>(String operationName, T Function() operation) {
    _profiler.startOperation(operationName);
    try {
      final result = operation();
      return result;
    } finally {
      _profiler.endOperation(operationName);
    }
  }

  /// Record a database write
  void recordWrite(String operation, String table, Map<String, dynamic> data,
      {String? taskId, String? categoryId}) {
    _profiler.recordDatabaseWrite(operation, table, data,
        taskId: taskId, categoryId: categoryId);
  }

  /// Record a cache operation
  void recordCacheOp(String operation, int taskCount, {String? details}) {
    _profiler.recordCacheOperation(operation, taskCount, details: details);
  }

  /// Take a memory snapshot
  void snapshotMemory(String context, {int? taskCount, int? cacheSize}) {
    _profiler.takeMemorySnapshot(context,
        taskCount: taskCount, cacheSize: cacheSize);
  }

  /// Get performance summary
  Map<String, dynamic> getPerformanceSummary() =>
      _profiler.getPerformanceSummary();

  /// Get detailed performance report
  String getDetailedReport() => _profiler.getDetailedReport();
}
