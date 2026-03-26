class ShareSubscriber {
  final String userId;
  final String? subscriberName;
  final DateTime sharedAt;

  const ShareSubscriber({
    required this.userId,
    this.subscriberName,
    required this.sharedAt,
  });

  factory ShareSubscriber.fromJson(Map<String, dynamic> json) {
    return ShareSubscriber(
      userId: json['user_id'] as String,
      subscriberName: json['subscriber_name'] as String?,
      sharedAt: DateTime.parse(json['shared_at'] as String),
    );
  }
}
