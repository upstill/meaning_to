class ShareInvitation {
  final String id;
  final int categoryId;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? usedAt;
  final String? recipientEmail;

  const ShareInvitation({
    required this.id,
    required this.categoryId,
    required this.createdAt,
    this.expiresAt,
    this.usedAt,
    this.recipientEmail,
  });

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool get isUsed => usedAt != null;

  bool get isActive => !isExpired && !isUsed;

  factory ShareInvitation.fromJson(Map<String, dynamic> json) {
    return ShareInvitation(
      id: json['id'] as String,
      categoryId: json['category_id'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      usedAt: json['used_at'] != null
          ? DateTime.parse(json['used_at'] as String)
          : null,
      recipientEmail: json['recipient_email'] as String?,
    );
  }
}
