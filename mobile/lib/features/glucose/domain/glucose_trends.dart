/// `GET /glucose/trends?days=30` (API_CONTRACT.md §3). The contract names
/// `daily[]` and `distribution{}` without enumerating their inner shape;
/// both are kept as loosely-typed maps and only `series`/`stats` (fully
/// specified) drive the chart and stat tiles.
class GlucoseTrends {
  const GlucoseTrends({
    required this.days,
    required this.count,
    required this.series,
    required this.daily,
    required this.stats,
    required this.distribution,
  });

  final int days;
  final int count;
  final List<GlucoseTrendPoint> series;
  final List<Map<String, dynamic>> daily;
  final GlucoseStats stats;
  final Map<String, dynamic> distribution;

  factory GlucoseTrends.fromJson(Map<String, dynamic> json) {
    return GlucoseTrends(
      days: (json['days'] as num?)?.toInt() ?? 30,
      count: (json['count'] as num?)?.toInt() ?? 0,
      series: (json['series'] as List<dynamic>? ?? const [])
          .map((e) => GlucoseTrendPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      daily: (json['daily'] as List<dynamic>? ?? const [])
          .map((e) => e as Map<String, dynamic>)
          .toList(),
      stats: GlucoseStats.fromJson(json['stats'] as Map<String, dynamic>? ?? const {}),
      distribution: (json['distribution'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

class GlucoseTrendPoint {
  const GlucoseTrendPoint({required this.at, required this.value, this.flag, this.context});

  final DateTime? at;
  final num value;

  /// severe_low | low | in_range | high | very_high | critical_high.
  ///
  /// The server has always sent this; the client used to drop it and any screen
  /// wanting to say whether a reading was high had to re-derive the thresholds
  /// locally. Two copies of a clinical range is one too many.
  final String? flag;

  /// fasting | post_meal | random — the same reading means different things
  /// before and after a meal.
  final String? context;

  bool get isOutOfRange => flag != null && flag != 'in_range';

  factory GlucoseTrendPoint.fromJson(Map<String, dynamic> json) {
    return GlucoseTrendPoint(
      at: json['at'] == null ? null : DateTime.tryParse(json['at'].toString()),
      value: json['value'] as num? ?? 0,
      flag: json['flag']?.toString(),
      context: json['context']?.toString(),
    );
  }
}

class GlucoseStats {
  const GlucoseStats({
    required this.average,
    required this.min,
    required this.max,
    required this.coefficientOfVariation,
    required this.timeInRangePercent,
    required this.estimatedHba1c,
  });

  final num? average;
  final num? min;
  final num? max;
  final num? coefficientOfVariation;
  final num? timeInRangePercent;
  final num? estimatedHba1c;

  factory GlucoseStats.fromJson(Map<String, dynamic> json) {
    return GlucoseStats(
      average: json['average'] as num?,
      min: json['min'] as num?,
      max: json['max'] as num?,
      coefficientOfVariation: json['coefficientOfVariation'] as num?,
      timeInRangePercent: json['timeInRangePercent'] as num?,
      estimatedHba1c: json['estimatedHba1c'] as num?,
    );
  }
}
