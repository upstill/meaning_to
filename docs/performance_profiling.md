# Performance Profiling System

## Overview

The performance profiling system has been implemented to identify and monitor potential bottlenecks when dealing with large numbers of tasks (100+ tasks per category). This system tracks cache operations, database writes, and operation timing to help identify performance issues.

## Components

### 1. PerformanceProfiler (`lib/utils/performance_profiler.dart`)

The core profiling engine that tracks:
- **Operation timing**: Measures execution time of key operations
- **Database writes**: Tracks frequency and volume of database operations
- **Cache operations**: Monitors cache updates and operations
- **Memory snapshots**: Records memory usage at key points

### 2. PerformanceMonitoring Mixin

A mixin that provides easy integration of performance monitoring into any class:
- `monitorOperation()`: Wraps async operations with timing
- `monitorSyncOperation()`: Wraps sync operations with timing
- `recordWrite()`: Records database write operations
- `recordCacheOp()`: Records cache operations
- `snapshotMemory()`: Takes memory usage snapshots

### 3. PerformanceMonitorScreen (`lib/performance_monitor_screen.dart`)

A debug UI screen that displays:
- Performance summary and statistics
- Operation timing breakdown
- Database write frequency analysis
- Cache operation metrics
- Detailed performance reports

## Integration

### CacheManager Integration

The CacheManager has been enhanced with performance monitoring:

```dart
class CacheManager with PerformanceMonitoring {
  // All cache operations are now monitored
  Future<void> addTask(Task task) async {
    return monitorOperation('addTask', () async {
      // ... existing code ...
      
      // Record database write
      recordWrite('create_task', 'Tasks', taskData, 
        taskId: savedTask.id.toString(), 
        categoryId: _currentCategory!.id.toString());
      
      // Record cache operation
      recordCacheOp('add_task_saved', _currentTasks!.length);
    });
  }
}
```

### Accessing Performance Data

#### From Code
```dart
final cacheManager = CacheManager();

// Get performance summary
final stats = cacheManager.getPerformanceStats();

// Get detailed report
final report = cacheManager.getPerformanceReport();

// Clear performance data
cacheManager.clearPerformanceData();
```

#### From UI (Debug Mode)
In debug mode, a performance monitor button appears in the home screen AppBar. Tap it to access the PerformanceMonitorScreen.

## Performance Thresholds

The system automatically detects and warns about:

- **Slow operations**: > 100ms average execution time
- **Very slow operations**: > 500ms average execution time
- **High database write frequency**: > 60 writes per minute
- **High cache operation frequency**: > 100 operations per minute

## Key Metrics Tracked

### Operation Timing
- Average, median, min, max execution times
- Total execution time
- Call frequency

### Database Writes
- Total writes per session
- Writes by operation type
- Recent write frequency (last 5 minutes)
- Data size and field count

### Cache Operations
- Total operations per session
- Operations by type
- Recent operation frequency
- Task count context

### Memory Usage
- Memory snapshots at key points
- Task count and cache size tracking

## Performance Recommendations

The system provides automatic recommendations based on detected patterns:

### High Database Write Frequency
- **Problem**: Too many individual database writes
- **Solution**: Implement write batching for bulk operations
- **Example**: Batch multiple task updates into a single transaction

### High Cache Operation Frequency
- **Problem**: Too many cache updates causing UI lag
- **Solution**: Implement cache update debouncing
- **Example**: Debounce rapid UI changes before updating cache

### Slow Operations
- **Problem**: Operations taking too long
- **Solution**: Optimize algorithms or implement caching
- **Example**: Cache expensive calculations or database queries

### Large Task Lists
- **Problem**: Performance degrades with 100+ tasks
- **Solution**: Implement pagination or lazy loading
- **Example**: Load tasks in chunks of 50, implement virtual scrolling

## Usage Examples

### Monitoring a Custom Operation
```dart
class MyService with PerformanceMonitoring {
  Future<void> processTasks(List<Task> tasks) async {
    return monitorOperation('processTasks', () async {
      // Record cache operation
      recordCacheOp('process_tasks', tasks.length);
      
      for (final task in tasks) {
        // Process each task
        await processTask(task);
        
        // Record database write
        recordWrite('update_task', 'Tasks', task.toJson(), 
          taskId: task.id.toString());
      }
    });
  }
}
```

### Taking Memory Snapshots
```dart
// Take snapshot before heavy operation
snapshotMemory('before_bulk_import', taskCount: currentTasks.length);

// Perform heavy operation
await importLargeTaskList();

// Take snapshot after operation
snapshotMemory('after_bulk_import', taskCount: currentTasks.length);
```

## Debug Output

The system provides real-time debug output:

```
🚨 HIGH DATABASE WRITE FREQUENCY: 65 writes in the last minute
   Consider implementing write batching or reducing update frequency

⚠️ SLOW OPERATION: _sortTasks took 150ms

🚨 VERY SLOW OPERATION: _loadTasksFromApi took 800ms
```

## Performance Report Example

```
=== PERFORMANCE PROFILER REPORT ===
Generated: 2024-01-15 10:30:00.000

OPERATION TIMING:
  addTask:
    Count: 25
    Avg: 45ms
    Median: 42ms
    Min: 35ms
    Max: 120ms
    Total: 1125ms

  _sortTasks:
    Count: 50
    Avg: 12ms
    Median: 10ms
    Min: 8ms
    Max: 45ms
    Total: 600ms

DATABASE WRITES:
  Total writes: 25
  Recent writes (5min): 15
  Writes by operation:
    create_task: 10
    update_task: 15

CACHE OPERATIONS:
  Total operations: 75
  Recent operations (5min): 45
  Operations by type:
    add_task_saved: 10
    update_task_saved: 15
    sort_tasks: 50

PERFORMANCE RECOMMENDATIONS:
  ⚠️ _sortTasks is slow (12ms avg) - monitor closely
  📊 _sortTasks called frequently (50 times) - consider caching
  💡 Consider implementing:
    - Database write batching for bulk operations
    - Cache update debouncing for frequent changes
    - Lazy loading for large task lists
    - Pagination for categories with 100+ tasks
```

## Benefits

1. **Proactive Monitoring**: Identify performance issues before they become critical
2. **Data-Driven Optimization**: Make optimization decisions based on actual metrics
3. **Debugging Support**: Quickly identify bottlenecks during development
4. **Scalability Planning**: Understand how the app performs with large datasets
5. **User Experience**: Ensure smooth performance even with 100+ tasks

## Future Enhancements

- **Real-time monitoring**: Live performance dashboard
- **Performance alerts**: Automatic notifications for performance issues
- **Historical tracking**: Long-term performance trends
- **Automated optimization**: Automatic performance improvements
- **Integration with analytics**: Correlate performance with user behavior 