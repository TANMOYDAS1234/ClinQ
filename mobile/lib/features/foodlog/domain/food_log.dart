/// One meal the patient logged for their dietician.
class FoodLogEntry {
  const FoodLogEntry({required this.id, required this.mealType, required this.note, this.photoUrl, this.createdAt});

  final String id;
  final String mealType; // breakfast | lunch | dinner | snack | other
  final String note;
  final String? photoUrl; // /api/v1/uploads/:id/raw
  final DateTime? createdAt;

  factory FoodLogEntry.fromJson(Map<String, dynamic> j) => FoodLogEntry(
        id: j['id']?.toString() ?? '',
        mealType: j['mealType']?.toString() ?? 'other',
        note: j['note']?.toString() ?? '',
        photoUrl: (j['photoUrl'] == null || j['photoUrl'].toString().isEmpty) ? null : j['photoUrl'].toString(),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal(),
      );
}
