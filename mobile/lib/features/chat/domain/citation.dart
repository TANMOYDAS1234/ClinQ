/// `{ id, title, source }` — API_CONTRACT.md §2.
class Citation {
  const Citation({required this.id, required this.title, required this.source});

  final String id;
  final String title;
  final String source;

  factory Citation.fromJson(Map<String, dynamic> json) {
    return Citation(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
    );
  }
}
