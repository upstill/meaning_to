import 'package:flutter/material.dart';
import 'package:meaning_to/utils/cache_manager.dart';

/// Screen for monitoring performance metrics and cache operations
/// Useful for debugging performance issues with large numbers of tasks
class PerformanceMonitorScreen extends StatefulWidget {
  const PerformanceMonitorScreen({super.key});

  @override
  State<PerformanceMonitorScreen> createState() =>
      _PerformanceMonitorScreenState();
}

class _PerformanceMonitorScreenState extends State<PerformanceMonitorScreen> {
  final CacheManager _cacheManager = CacheManager();
  Map<String, dynamic> _performanceStats = {};
  String _detailedReport = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPerformanceData();
  }

  Future<void> _loadPerformanceData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final stats = _cacheManager.getPerformanceStats();
      final report = _cacheManager.getPerformanceReport();

      setState(() {
        _performanceStats = stats;
        _detailedReport = report;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading performance data: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPerformanceData,
            tooltip: 'Refresh Data',
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _cacheManager.clearPerformanceData();
              _loadPerformanceData();
            },
            tooltip: 'Clear Data',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryCard(),
                  const SizedBox(height: 16),
                  _buildTimingStatsCard(),
                  const SizedBox(height: 16),
                  _buildDatabaseWritesCard(),
                  const SizedBox(height: 16),
                  _buildCacheOperationsCard(),
                  const SizedBox(height: 16),
                  _buildDetailedReportCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Performance Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
                'Cache Status: ${_cacheManager.isInitialized ? "Initialized" : "Not Initialized"}'),
            if (_cacheManager.isInitialized) ...[
              Text(
                  'Current Category: ${_cacheManager.currentCategory?.headline ?? "None"}'),
              Text('Task Count: ${_cacheManager.taskCount}'),
              Text('Unfinished Tasks: ${_cacheManager.unfinishedTaskCount}'),
            ],
            const SizedBox(height: 8),
            Text(
                'Memory Snapshots: ${_performanceStats['memory_snapshots'] ?? 0}'),
          ],
        ),
      ),
    );
  }

  Widget _buildTimingStatsCard() {
    final timingStats =
        _performanceStats['timing_stats'] as Map<String, dynamic>?;

    if (timingStats == null || timingStats.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No timing data available'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Operation Timing',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...timingStats.entries.map((entry) {
              final stats = entry.value as Map<String, dynamic>;
              final avgMs = stats['avg_ms'] as int? ?? 0;
              final count = stats['count'] as int? ?? 0;
              final maxMs = stats['max_ms'] as int? ?? 0;

              Color statusColor = Colors.green;
              if (avgMs > 500)
                statusColor = Colors.red;
              else if (avgMs > 100) statusColor = Colors.orange;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        entry.key,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${avgMs}ms avg',
                        style: TextStyle(color: statusColor),
                      ),
                    ),
                    Expanded(
                      child: Text('$count calls'),
                    ),
                    Expanded(
                      child: Text('${maxMs}ms max'),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildDatabaseWritesCard() {
    final writeStats =
        _performanceStats['database_writes'] as Map<String, dynamic>?;

    if (writeStats == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No database write data available'),
        ),
      );
    }

    final totalWrites = writeStats['total_writes'] as int? ?? 0;
    final recentWrites = writeStats['recent_writes'] as int? ?? 0;
    final writesByOp =
        writeStats['writes_by_operation'] as Map<String, dynamic>? ?? {};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Database Writes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Total Writes: $totalWrites'),
            Text(
              'Recent Writes (5min): $recentWrites',
              style: TextStyle(
                color: recentWrites > 50 ? Colors.red : Colors.green,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (writesByOp.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Writes by Operation:',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              ...writesByOp.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(left: 16.0, top: 4.0),
                  child: Text('${entry.key}: ${entry.value}'),
                );
              }).toList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCacheOperationsCard() {
    final cacheStats =
        _performanceStats['cache_operations'] as Map<String, dynamic>?;

    if (cacheStats == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No cache operation data available'),
        ),
      );
    }

    final totalOps = cacheStats['total_operations'] as int? ?? 0;
    final recentOps = cacheStats['recent_operations'] as int? ?? 0;
    final opsByType =
        cacheStats['operations_by_type'] as Map<String, dynamic>? ?? {};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cache Operations',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Total Operations: $totalOps'),
            Text(
              'Recent Operations (5min): $recentOps',
              style: TextStyle(
                color: recentOps > 80 ? Colors.red : Colors.green,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (opsByType.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Operations by Type:',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              ...opsByType.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(left: 16.0, top: 4.0),
                  child: Text('${entry.key}: ${entry.value}'),
                );
              }).toList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedReportCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Detailed Report',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    // Copy to clipboard
                    // You can implement clipboard functionality here
                  },
                  tooltip: 'Copy Report',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 300,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  _detailedReport.isEmpty
                      ? 'No detailed report available'
                      : _detailedReport,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
