class Category {
  final String id;
  final String headline;
  final String invitation;
  final String ownerId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Category({
    required this.id,
    required this.headline,
    required this.invitation,
    required this.ownerId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'],
      headline: json['headline'],
      invitation: json['invitation'],
      ownerId: json['owner_id'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'headline': headline,
      'invitation': invitation,
      'owner_id': ownerId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
} 