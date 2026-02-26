import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/performance_profiler.dart';

void main() {
  group('PerformanceProfiler Tests', () {
    late PerformanceProfiler profiler;

    setUp(() {
      profiler = PerformanceProfiler();
      profiler.clear();
    });

    tearDown(() {
      profiler.clear();
    });

    test('should track operation timing', () async {
      // Start timing an operation
      profiler.startOperation('test_operation');

      // Simulate some work
      await Future.delayed(Duration(milliseconds: 50));

      // End timing
      profiler.endOperation('test_operation');

      // Get performance summary
      final summary = profiler.getPerformanceSummary();
      final timingStats = summary['timing_stats'] as Map<String, dynamic>;

      expect(timingStats, contains('test_operation'));
      expect(timingStats['test_operation']['count'], 1);
      expect(timingStats['test_operation']['avg_ms'], greaterThan(40));
      expect(timingStats['test_operation']['avg_ms'], lessThan(100));
    });

    test('should track database writes', () {
      final testData = {'field1': 'value1', 'field2': 'value2'};

      profiler.recordDatabaseWrite('test_write', 'TestTable', testData,
          taskId: '123', categoryId: '456');

      final summary = profiler.getPerformanceSummary();
      final writeStats = summary['database_writes'] as Map<String, dynamic>;

      expect(writeStats['total_writes'], 1);
      expect(writeStats['writes_by_operation']['test_write'], 1);
    });

    test('should track cache operations', () {
      profiler.recordCacheOperation('test_cache_op', 100,
          details: 'test_details');

      final summary = profiler.getPerformanceSummary();
      final cacheStats = summary['cache_operations'] as Map<String, dynamic>;

      expect(cacheStats['total_operations'], 1);
      expect(cacheStats['operations_by_type']['test_cache_op'], 1);
    });

    test('should take memory snapshots', () {
      profiler.takeMemorySnapshot('test_context',
          taskCount: 50, cacheSize: 1024);

      final summary = profiler.getPerformanceSummary();
      expect(summary['memory_snapshots'], 1);
    });

    test('should generate detailed report', () {
      // Add some test data
      profiler.startOperation('test_op');
      profiler.endOperation('test_op');
      profiler.recordDatabaseWrite('test_write', 'TestTable', {'test': 'data'});
      profiler.recordCacheOperation('test_cache', 10);

      final report = profiler.getDetailedReport();

      expect(report, contains('PERFORMANCE PROFILER REPORT'));
      expect(report, contains('test_op'));
      expect(report, contains('test_write'));
      expect(report, contains('test_cache'));
    });

    test('should detect high write frequency', () {
      // Add many writes quickly
      for (int i = 0; i < 70; i++) {
        profiler
            .recordDatabaseWrite('test_write', 'TestTable', {'test': 'data'});
      }

      // The profiler should log a warning about high frequency
      // We can't easily test the print output, but we can verify the data is recorded
      final summary = profiler.getPerformanceSummary();
      final writeStats = summary['database_writes'] as Map<String, dynamic>;

      expect(writeStats['total_writes'], 70);
      expect(writeStats['recent_writes'], greaterThan(50));
    });

    test('should get recent operations', () async {
      // Add some operations
      profiler.recordCacheOperation('old_op', 10);

      // Wait a bit
      await Future.delayed(Duration(milliseconds: 10));

      profiler.recordCacheOperation('recent_op', 20);

      final recentOps = profiler.getRecentCacheOperations(1); // Last minute
      expect(recentOps.length, 2);

      final veryRecentOps = profiler.getRecentCacheOperations(1); // Last minute
      expect(veryRecentOps.length, 2); // Both should be recent
    });
  });

  group('PerformanceMonitoring Mixin Tests', () {
    late TestClass testClass;

    setUp(() {
      testClass = TestClass();
    });

    tearDown(() {
      // Clear the profiler to ensure clean state between tests
      final profiler = PerformanceProfiler();
      profiler.clear();
    });

    test('should monitor async operations', () async {
      final result = await testClass.monitorOperation('test_async', () async {
        await Future.delayed(Duration(milliseconds: 30));
        return 'test_result';
      });

      expect(result, 'test_result');

      final summary = testClass.getPerformanceSummary();
      final timingStats = summary['timing_stats'] as Map<String, dynamic>;
      expect(timingStats, contains('test_async'));
    });

    test('should monitor sync operations', () {
      final result = testClass.monitorSyncOperation('test_sync', () {
        return 'sync_result';
      });

      expect(result, 'sync_result');

      final summary = testClass.getPerformanceSummary();
      final timingStats = summary['timing_stats'] as Map<String, dynamic>;
      expect(timingStats, contains('test_sync'));
    });

    test('should record writes and cache operations', () {
      testClass.recordWrite('test_write', 'TestTable', {'test': 'data'});
      testClass.recordCacheOp('test_cache', 25);

      final summary = testClass.getPerformanceSummary();
      final writeStats = summary['database_writes'] as Map<String, dynamic>;
      final cacheStats = summary['cache_operations'] as Map<String, dynamic>;

      expect(writeStats['total_writes'], 1);
      expect(cacheStats['total_operations'], 1);
    });
  });
}

// Test class that uses the PerformanceMonitoring mixin
class TestClass with PerformanceMonitoring {
  // This class can use all the performance monitoring methods
}
