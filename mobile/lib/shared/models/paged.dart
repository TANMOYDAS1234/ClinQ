/// Generic wrapper for the API's paged-list shape (API_CONTRACT.md
/// "Conventions"): `{ items, page, limit, total, hasMore }`.
class Paged<T> {
  const Paged({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.hasMore,
  });

  final List<T> items;
  final int page;
  final int limit;
  final int total;
  final bool hasMore;

  factory Paged.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    return Paged<T>(
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((e) => fromJsonT(e as Map<String, dynamic>))
          .toList(),
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 50,
      total: (json['total'] as num?)?.toInt() ?? 0,
      hasMore: json['hasMore'] as bool? ?? false,
    );
  }

  static Paged<T> empty<T>() =>
      Paged<T>(items: const [], page: 1, limit: 50, total: 0, hasMore: false);
}
