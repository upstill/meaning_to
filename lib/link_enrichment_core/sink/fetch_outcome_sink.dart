/// Callback interface for recording per-fetch outcomes for empirical analysis.
///
/// The default implementation ([FetchOutcomeSink.noOp]) discards all events.
/// Replace with a persistent implementation when per-site, per-context fetch
/// logging is needed.
abstract class FetchOutcomeSink {
  const FetchOutcomeSink();

  void record({
    required String url,
    required String siteId,
    required String context,
    required String method,
    required bool success,
    required int responseMs,
  });

  static const FetchOutcomeSink noOp = _NoOpSink();
}

class _NoOpSink extends FetchOutcomeSink {
  const _NoOpSink();

  @override
  void record({
    required String url,
    required String siteId,
    required String context,
    required String method,
    required bool success,
    required int responseMs,
  }) {}
}
