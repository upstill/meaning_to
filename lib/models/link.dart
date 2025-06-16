/// A model class representing a link in the application
class Link {
  /// The title of the link
  final String title;

  /// The URL of the link
  final String url;

  /// Optional description of the link
  final String? description;

  /// Creates a new Link instance
  Link({
    required this.title,
    required this.url,
    this.description,
  });

  /// Creates a Link from a JSON map
  factory Link.fromJson(Map<String, dynamic> json) {
    return Link(
      title: json['title'] as String,
      url: json['url'] as String,
      description: json['description'] as String?,
    );
  }

  /// Converts the Link to a JSON map
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      if (description != null) 'description': description,
    };
  }

  @override
  String toString() {
    return 'Link(title: $title, url: $url, description: $description)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Link &&
        other.title == title &&
        other.url == url &&
        other.description == description;
  }

  @override
  int get hashCode => title.hashCode ^ url.hashCode ^ description.hashCode;
}
