class Category {
  final int id;
  String headline;
  String? invitation;
  final String ownerId;
  final DateTime createdAt;
  DateTime? updatedAt;
  final int? originalId;
  final DateTime? triggersAt;
  final String? template;
  final DateTime? lastAccess;
  bool isPrivate;
  bool tasksArePrivate;

  Category({
    required this.id,
    required this.headline,
    this.invitation,
    required this.ownerId,
    required this.createdAt,
    this.updatedAt,
    this.originalId,
    this.triggersAt,
    this.template,
    this.lastAccess,
    this.isPrivate = false,
    this.tasksArePrivate = true,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Category && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as int,
      headline: json['headline'] as String,
      invitation: json['invitation'] as String?,
      ownerId: json['owner_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      originalId: json['original_id'] as int?,
      triggersAt: json['triggers_at'] != null
          ? DateTime.parse(json['triggers_at'] as String)
          : null,
      template: json['template'] as String?,
      lastAccess: json['last_access'] != null
          ? DateTime.parse(json['last_access'] as String)
          : null,
      isPrivate: json['private'] as bool? ?? false,
      tasksArePrivate: json['tasks_are_private'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'headline': headline,
      'invitation': invitation,
      'owner_id': ownerId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'original_id': originalId,
      'triggers_at': triggersAt?.toIso8601String(),
      'template': template,
      'last_access': lastAccess?.toIso8601String(),
      'private': isPrivate,
      'tasks_are_private': tasksArePrivate,
    };
  }
}
