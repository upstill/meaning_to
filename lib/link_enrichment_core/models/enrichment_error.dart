enum EnrichmentErrorCode {
  invalidUrl,
  timeout,
  blocked,
  parseFailure,
  networkFailure,
  unknown,
}

class EnrichmentError {
  final EnrichmentErrorCode code;
  final String message;

  const EnrichmentError(this.code, this.message);
}
